-- =============================================================================
-- 05_marts.sql
-- Builds the analysis-ready MART tables from STAGING.
-- Run from the repo root:
--     snow sql -c metro -f sql/05_marts.sql
--
-- Tables:
--   DIM_LINE            one row per line: forecast and chart rules, data caveats
--   DIM_CALENDAR        one row per date: Power BI date table
--   DAILY_LINE_DEMAND   date x line x time band: feeds the forecast and trends page
--   STATION_SUMMARY     station x day type: stations page and map
--   PEAK_LOAD_SERVICES  train x line x direction (normal weekdays): busiest services
--   HOURLY_PROFILE      line x day type x half hour: time-of-day heatmap
--
-- Two rules used throughout (see docs/data_quality_notes.md):
--   * Averages are per day of that type (total / number of such days), so a day
--     type with more days doesn't look bigger.
--   * Nothing is dropped. Lines that shouldn't be ranked or forecast are flagged
--     in DIM_LINE, and each page or model filters on those flags.
--
-- Safe to re-run: every table is CREATE OR REPLACE.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE METRO_WH;
USE DATABASE METRO_DB;
USE SCHEMA MART;

-- -----------------------------------------------------------------------------
-- 1. DIM_LINE: one row per line, holding the line-level decisions.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE MART.DIM_LINE
COMMENT = 'One row per line: totals, zero-row share, and the flags that decide where each line appears'
AS
WITH line_stats AS (
    SELECT line_name,
           COUNT(*)                                       AS stop_rows,
           SUM(passenger_boardings)                       AS annual_boardings,
           COUNT(DISTINCT station_name)                   AS stations_served,
           ROUND(100 * COUNT_IF(passenger_boardings = 0 AND passenger_alightings = 0
                                AND passenger_arrival_load = 0 AND passenger_departure_load = 0)
                     / COUNT(*), 1)                       AS zero_row_pct
    FROM STAGING.PASSENGER_COUNTS
    GROUP BY line_name
)
SELECT
    line_name,
    -- Display name for charts. Only the non-corridor 'line' gets a different label.
    IFF(line_name = 'Richmond and City Loop', 'City Loop & short services', line_name) AS line_label,
    stop_rows,
    annual_boardings,
    stations_served,
    zero_row_pct,
    -- A corridor line is a real line a passenger would name. Richmond and City Loop
    -- is short city services (0.29% of boardings): kept in totals, not ranked.
    line_name <> 'Richmond and City Loop'                                         AS is_corridor_line,
    -- Forecast excludes the non-corridor line, Stony Point (36.8% zero rows) and
    -- Flemington Racecourse (event days only, 7-36% zero rows by month).
    line_name NOT IN ('Richmond and City Loop', 'Stony Point', 'Flemington Racecourse') AS include_in_forecast,
    CASE
        WHEN line_name = 'Richmond and City Loop'  THEN 'Short city services, not a corridor line'
        WHEN line_name = 'Flemington Racecourse'   THEN 'Runs on event days only'
        WHEN zero_row_pct > 10                     THEN 'About ' || ROUND(zero_row_pct)::VARCHAR
                                                        || '% of stop records have no data; levels likely understated'
    END                                                                           AS data_caveat,
    -- Rank among corridor lines only, busiest = 1.
    IFF(is_corridor_line,
        RANK() OVER (PARTITION BY is_corridor_line ORDER BY annual_boardings DESC),
        NULL)                                                                     AS boardings_rank
FROM line_stats;

-- -----------------------------------------------------------------------------
-- 2. DIM_CALENDAR: one row per date, 1 Jul 2024 to 31 Dec 2025.
--    day_type comes from the source where we have data (FY2024-25), and is
--    built from the calendar flags for the forecast months after that. Check 5
--    showed the two agree on all 365 overlapping dates.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE MART.DIM_CALENDAR
COMMENT = 'Date table for Power BI and the forecast: calendar flags plus day type'
AS
WITH source_day_type AS (
    SELECT DISTINCT business_date, day_type FROM STAGING.PASSENGER_COUNTS
)
SELECT
    c.calendar_date,
    c.day_of_week,
    DAYOFWEEKISO(c.calendar_date)                         AS day_of_week_num,   -- 1 = Monday, for sorting
    c.is_weekday,
    c.is_public_holiday,
    c.holiday_name,
    c.is_school_holiday,
    COALESCE(s.day_type,
             CASE WHEN c.is_public_holiday        THEN 'Public Holiday'
                  WHEN c.day_of_week = 'Saturday' THEN 'Saturday'
                  WHEN c.day_of_week = 'Sunday'   THEN 'Sunday'
                  WHEN c.is_school_holiday        THEN 'School Holiday'
                  ELSE                                 'Normal Weekday'
             END)                                         AS day_type,
    s.business_date IS NOT NULL                           AS has_passenger_data,
    DATE_TRUNC('week', c.calendar_date)                   AS week_start,        -- Monday
    DATE_TRUNC('month', c.calendar_date)                  AS month_start,
    TO_CHAR(c.calendar_date, 'Mon YYYY')                  AS month_label,
    c.fiscal_month,
    c.fiscal_year
FROM STAGING.CALENDAR c
LEFT JOIN source_day_type s ON s.business_date = c.calendar_date;

-- -----------------------------------------------------------------------------
-- 3. DAILY_LINE_DEMAND: date x line x time band.
--    The forecast reads the weekday AM Peak rows of this table.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE MART.DAILY_LINE_DEMAND
COMMENT = 'Daily boardings by line and time band, with calendar flags. Forecast input'
AS
SELECT
    p.business_date,
    p.line_name,
    p.time_band,
    c.day_type,
    c.is_weekday,
    c.is_public_holiday,
    c.is_school_holiday,
    SUM(p.passenger_boardings)                            AS boardings,
    SUM(p.passenger_alightings)                           AS alightings,
    MAX(p.passenger_departure_load)                       AS max_departure_load,
    COUNT(DISTINCT p.train_number)                        AS services
FROM STAGING.PASSENGER_COUNTS p
JOIN MART.DIM_CALENDAR c ON c.calendar_date = p.business_date
GROUP BY 1, 2, 3, 4, 5, 6, 7;

-- -----------------------------------------------------------------------------
-- 4. STATION_SUMMARY: station x day type, plus the reconciliation against
--    station entries (check 7 in the data quality notes).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE MART.STATION_SUMMARY
COMMENT = 'Average daily boardings per station by day type, AM peak share, rank, and boardings per barrier entry'
AS
WITH days_per_type AS (
    -- How many days of each type are in the data, e.g. 199 normal weekdays.
    SELECT day_type, COUNT(*) AS days_of_type
    FROM MART.DIM_CALENDAR
    WHERE has_passenger_data
    GROUP BY day_type
),
station_day_type AS (
    SELECT station_name,
           day_type,
           SUM(passenger_boardings)                                  AS boardings,
           SUM(IFF(time_band = 'AM Peak', passenger_boardings, 0))   AS am_peak_boardings,
           ANY_VALUE(station_latitude)                               AS station_latitude,
           ANY_VALUE(station_longitude)                              AS station_longitude
    FROM STAGING.PASSENGER_COUNTS
    GROUP BY station_name, day_type
),
station_lines AS (
    -- The corridor lines serving each station, e.g. 'Cranbourne, Pakenham'.
    SELECT p.station_name,
           LISTAGG(DISTINCT p.line_name, ', ') WITHIN GROUP (ORDER BY p.line_name) AS lines_served
    FROM STAGING.PASSENGER_COUNTS p
    JOIN MART.DIM_LINE l ON l.line_name = p.line_name AND l.is_corridor_line
    GROUP BY p.station_name
),
station_annual AS (
    SELECT station_name, SUM(passenger_boardings) AS annual_boardings
    FROM STAGING.PASSENGER_COUNTS
    GROUP BY station_name
),
vline_stations AS (
    SELECT DISTINCT TRIM(station_name) AS station_name
    FROM RAW.PASSENGER_COUNTS
    WHERE TRIM(mode) = 'V/Line'
)
SELECT
    s.station_name,
    s.day_type,
    d.days_of_type,
    s.boardings                                                   AS total_boardings,
    ROUND(s.boardings / d.days_of_type)                           AS avg_daily_boardings,
    ROUND(s.am_peak_boardings / d.days_of_type)                   AS avg_daily_am_peak_boardings,
    ROUND(100 * s.am_peak_boardings / NULLIF(s.boardings, 0), 1)  AS am_peak_share_pct,
    RANK() OVER (PARTITION BY s.day_type ORDER BY s.boardings DESC) AS network_rank,
    sl.lines_served,
    s.station_latitude,
    s.station_longitude,
    -- Annual reconciliation with barrier entries (same value on every day type row).
    a.annual_boardings,
    e.pax_annual                                                  AS annual_entries,
    ROUND(a.annual_boardings / NULLIF(e.pax_annual, 0), 2)        AS boardings_per_entry,
    -- Transfer hubs: over 2 boardings per entry, because passengers changing
    -- trains count as new boardings. Flinders Street, Richmond, North Melbourne.
    boardings_per_entry >= 2                                      AS is_transfer_hub,
    s.station_name IN (SELECT station_name FROM vline_stations)   AS has_vline
FROM station_day_type s
JOIN days_per_type d          ON d.day_type = s.day_type
JOIN station_annual a         ON a.station_name = s.station_name
LEFT JOIN station_lines sl    ON sl.station_name = s.station_name
LEFT JOIN STAGING.STATION_ENTRIES e ON e.station_name = s.station_name;

-- -----------------------------------------------------------------------------
-- 5. PEAK_LOAD_SERVICES: the busiest regular services on normal weekdays.
--    Step 1: for each train on each day, find the stop where it was fullest
--            (QUALIFY keeps only the top row per train per day).
--    Step 2: average those daily peaks per train number. Train numbers are
--            stable: the median train runs 194 of the 199 normal weekdays.
--    Only regular services (running on at least half the normal weekdays)
--    are ranked. Otherwise one-off event trains, e.g. a single late train
--    from Flemington Racecourse, top the list on one busy night.
--    The source model has no capacity limit, so very high loads mean
--    "very crowded", not an exact count.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE MART.PEAK_LOAD_SERVICES
COMMENT = 'Average peak departure load per regular service on normal weekdays, with where and when it peaks'
AS
WITH service_start AS (
    SELECT business_date, train_number, line_name, direction,
           MIN(departure_time_scheduled)                  AS first_departure,
           ANY_VALUE(origin_station)                      AS origin_station,
           ANY_VALUE(destination_station)                 AS destination_station
    FROM STAGING.PASSENGER_COUNTS
    WHERE day_type = 'Normal Weekday'
    GROUP BY 1, 2, 3, 4
),
daily_peak AS (
    SELECT business_date, train_number, line_name, direction,
           station_name                                   AS peak_station,
           departure_time_scheduled                       AS peak_time,
           time_band                                      AS peak_time_band,
           passenger_departure_load                       AS peak_load
    FROM STAGING.PASSENGER_COUNTS
    WHERE day_type = 'Normal Weekday'
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY business_date, train_number, line_name, direction
        ORDER BY passenger_departure_load DESC, stop_sequence_number) = 1
)
SELECT
    p.train_number,
    p.line_name,
    p.direction,
    MODE(s.origin_station)                                AS origin_station,
    MODE(s.destination_station)                           AS destination_station,
    MODE(s.first_departure)                               AS usual_first_departure,
    COUNT(*)                                              AS weekdays_run,
    ROUND(AVG(p.peak_load))                               AS avg_peak_load,
    MAX(p.peak_load)                                      AS max_peak_load,
    MODE(p.peak_station)                                  AS usual_peak_station,
    MODE(p.peak_time)                                     AS usual_peak_time,
    MODE(p.peak_time_band)                                AS usual_peak_time_band,
    weekdays_run >= (SELECT COUNT(*) / 2 FROM MART.DIM_CALENDAR
                     WHERE has_passenger_data AND day_type = 'Normal Weekday') AS is_regular_service
FROM daily_peak p
JOIN service_start s USING (business_date, train_number, line_name, direction)
GROUP BY p.train_number, p.line_name, p.direction;

-- Rank regular services only (irregular ones get NULL). Done as a second step
-- because a window function can't rank on a flag computed in the same SELECT.
CREATE OR REPLACE TABLE MART.PEAK_LOAD_SERVICES
COMMENT = 'Average peak departure load per service on normal weekdays, with where and when it peaks. load_rank covers regular services only'
AS
SELECT *,
       IFF(is_regular_service,
           RANK() OVER (PARTITION BY is_regular_service ORDER BY avg_peak_load DESC),
           NULL) AS load_rank
FROM MART.PEAK_LOAD_SERVICES;

-- -----------------------------------------------------------------------------
-- 6. HOURLY_PROFILE: line x day type x 30-minute block, average per day.
--    Rows with no scheduled time (time_band 'Unknown') have no block, so
--    they're left out here; they're 0.05% of boardings.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE MART.HOURLY_PROFILE
COMMENT = 'Average boardings per day by line, day type and 30-minute departure block'
AS
WITH days_per_type AS (
    SELECT day_type, COUNT(*) AS days_of_type
    FROM MART.DIM_CALENDAR
    WHERE has_passenger_data
    GROUP BY day_type
)
SELECT
    p.line_name,
    p.day_type,
    p.half_hour_block,
    TO_CHAR(p.half_hour_block, 'HH24:MI')                 AS half_hour_label,
    ANY_VALUE(p.time_band)                                AS time_band,
    d.days_of_type,
    SUM(p.passenger_boardings)                            AS total_boardings,
    ROUND(SUM(p.passenger_boardings) / d.days_of_type)    AS avg_daily_boardings
FROM STAGING.PASSENGER_COUNTS p
JOIN days_per_type d ON d.day_type = p.day_type
WHERE p.half_hour_block IS NOT NULL
GROUP BY p.line_name, p.day_type, p.half_hour_block, d.days_of_type;

-- -----------------------------------------------------------------------------
-- 7. Checks.
-- -----------------------------------------------------------------------------

-- Row counts.
SELECT 'DIM_LINE' AS table_name, COUNT(*) AS row_count FROM MART.DIM_LINE
UNION ALL SELECT 'DIM_CALENDAR',       COUNT(*) FROM MART.DIM_CALENDAR
UNION ALL SELECT 'DAILY_LINE_DEMAND',  COUNT(*) FROM MART.DAILY_LINE_DEMAND
UNION ALL SELECT 'STATION_SUMMARY',    COUNT(*) FROM MART.STATION_SUMMARY
UNION ALL SELECT 'PEAK_LOAD_SERVICES', COUNT(*) FROM MART.PEAK_LOAD_SERVICES
UNION ALL SELECT 'HOURLY_PROFILE',     COUNT(*) FROM MART.HOURLY_PROFILE;

-- Boardings must still add up to the staging total (224,374,850). The hourly
-- profile is expected to be short by exactly the 'Unknown' boardings (105,240).
WITH staging_total AS (
    SELECT SUM(passenger_boardings) AS total,
           SUM(IFF(time_band = 'Unknown', passenger_boardings, 0)) AS unknown_total
    FROM STAGING.PASSENGER_COUNTS
)
SELECT 'DIM_LINE' AS table_name, (SELECT SUM(annual_boardings) FROM MART.DIM_LINE) AS boardings,
       total AS expected, IFF(boardings = expected, 'OK', 'CHECK') AS result FROM staging_total
UNION ALL
SELECT 'DAILY_LINE_DEMAND', (SELECT SUM(boardings) FROM MART.DAILY_LINE_DEMAND),
       total, IFF((SELECT SUM(boardings) FROM MART.DAILY_LINE_DEMAND) = total, 'OK', 'CHECK') FROM staging_total
UNION ALL
SELECT 'STATION_SUMMARY', (SELECT SUM(total_boardings) FROM MART.STATION_SUMMARY),
       total, IFF((SELECT SUM(total_boardings) FROM MART.STATION_SUMMARY) = total, 'OK', 'CHECK') FROM staging_total
UNION ALL
SELECT 'HOURLY_PROFILE (excl. Unknown)', (SELECT SUM(total_boardings) FROM MART.HOURLY_PROFILE),
       total - unknown_total,
       IFF((SELECT SUM(total_boardings) FROM MART.HOURLY_PROFILE) = total - unknown_total, 'OK', 'CHECK')
FROM staging_total;

-- DIM_LINE as built: the flags and caveats should match the decisions.
SELECT line_label, annual_boardings, zero_row_pct, is_corridor_line, include_in_forecast,
       boardings_rank, data_caveat
FROM MART.DIM_LINE
ORDER BY boardings_rank NULLS LAST;

-- Transfer hubs flagged (expect Flinders Street, Richmond, North Melbourne).
SELECT DISTINCT station_name, boardings_per_entry, has_vline
FROM MART.STATION_SUMMARY
WHERE is_transfer_hub
ORDER BY boardings_per_entry DESC;

-- Regular vs irregular services.
SELECT is_regular_service, COUNT(*) AS services, MIN(weekdays_run) AS min_days, MAX(weekdays_run) AS max_days
FROM MART.PEAK_LOAD_SERVICES
GROUP BY 1;

-- Peek at the busiest regular services (full analysis in 06_analysis.sql).
SELECT load_rank, line_name, direction, train_number, usual_first_departure,
       origin_station, destination_station, weekdays_run, avg_peak_load,
       usual_peak_station, usual_peak_time
FROM MART.PEAK_LOAD_SERVICES
ORDER BY load_rank
LIMIT 5;
