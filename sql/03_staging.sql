-- =============================================================================
-- 03_staging.sql
-- Turns the all-text RAW tables into typed, cleaned STAGING tables.
-- Run from the repo root:
--     snow sql -c metro -f sql/03_staging.sql
--
-- What happens here:
--   * Text becomes real types (DATE, TIME, NUMBER, BOOLEAN) with TRY_ functions.
--     TRY_TO_NUMBER('abc') returns NULL instead of failing the whole query, and
--     04_data_quality_checks.sql counts those NULLs, so bad values get reported
--     rather than lost or hidden.
--   * Text fields are trimmed. On Day 2 no names needed trimming, but TRIM
--     protects the joins if a future file has stray spaces.
--   * Passenger counts keep Metro Trains only (V/Line is out of scope).
--   * New columns: half_hour_block and time_band, both from the scheduled
--     departure time. The source has no time-block column.
--
-- Safe to re-run: CREATE OR REPLACE rebuilds each table from RAW.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE METRO_WH;
USE DATABASE METRO_DB;
USE SCHEMA STAGING;

-- -----------------------------------------------------------------------------
-- 1. Passenger counts: one row per service x station stop x business date.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE STAGING.PASSENGER_COUNTS
COMMENT = 'Metro Trains passenger counts FY2024-25: typed, trimmed, with half_hour_block and time_band'
AS
WITH typed AS (
    SELECT
        TRY_TO_DATE(TRIM(business_date), 'YYYY-MM-DD')     AS business_date,
        TRIM(day_of_week)                                  AS day_of_week,
        TRIM(day_type)                                     AS day_type,
        TRIM(mode)                                         AS mode,
        TRIM(train_number)                                 AS train_number,   -- kept as text: it's an ID, not a quantity
        TRIM(line_name)                                    AS line_name,
        TRIM("GROUP")                                      AS line_group,     -- renamed: GROUP is a reserved word
        TRIM(direction)                                    AS direction,      -- U = towards Flinders Street, D = away
        TRIM(origin_station)                               AS origin_station,
        TRIM(destination_station)                          AS destination_station,
        TRIM(station_name)                                 AS station_name,
        TRY_TO_DOUBLE(station_latitude)                    AS station_latitude,
        TRY_TO_DOUBLE(station_longitude)                   AS station_longitude,
        TRY_TO_NUMBER(station_chainage)                    AS station_chainage,
        TRY_TO_NUMBER(stop_sequence_number)                AS stop_sequence_number,
        TRY_TO_TIME(TRIM(arrival_time_scheduled), 'HH24:MI:SS')   AS arrival_time_scheduled,
        TRY_TO_TIME(TRIM(departure_time_scheduled), 'HH24:MI:SS') AS departure_time_scheduled,
        TRY_TO_NUMBER(passenger_boardings)                 AS passenger_boardings,
        TRY_TO_NUMBER(passenger_alightings)                AS passenger_alightings,
        TRY_TO_NUMBER(passenger_arrival_load)              AS passenger_arrival_load,
        TRY_TO_NUMBER(passenger_departure_load)            AS passenger_departure_load
    FROM RAW.PASSENGER_COUNTS
    WHERE TRIM(mode) = 'Metro Trains'
)
SELECT
    typed.*,

    -- Start of the 30-minute block the departure falls in, e.g. 07:42 -> 07:30.
    -- Feeds the time-of-day heatmap.
    TIME_FROM_PARTS(HOUR(departure_time_scheduled),
                    IFF(MINUTE(departure_time_scheduled) < 30, 0, 30),
                    0)                                     AS half_hour_block,

    -- Time band. Times are compared as HH:MI:SS, so 07:00:00 is AM Peak and
    -- 08:59:59 is the last moment of it (an exclusive 09:00 upper bound).
    -- 'Unknown' = no scheduled time (13,777 rows, 0.09%): still counted in
    -- daily totals, but left out of peak analysis.
    CASE
        WHEN departure_time_scheduled IS NULL            THEN 'Unknown'
        WHEN departure_time_scheduled <  '07:00:00'::TIME THEN 'Early'
        WHEN departure_time_scheduled <  '09:00:00'::TIME THEN 'AM Peak'
        WHEN departure_time_scheduled <  '16:00:00'::TIME THEN 'Inter-peak'
        WHEN departure_time_scheduled <  '19:00:00'::TIME THEN 'PM Peak'
        ELSE                                                  'Evening'
    END                                                    AS time_band
FROM typed;

-- -----------------------------------------------------------------------------
-- 2. Station entries: one row per station, annual totals and daily averages.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE STAGING.STATION_ENTRIES
COMMENT = 'Annual metropolitan train station entries FY2024-25, typed. Values rounded to nearest 50 by DTP'
AS
SELECT
    TRIM(fin_year)                     AS fin_year,
    TRY_TO_NUMBER(stop_id)             AS stop_id,
    TRIM(stop_name)                    AS station_name,   -- same name as the passenger counts column, for joining
    TRY_TO_DOUBLE(stop_lat)            AS station_latitude,
    TRY_TO_DOUBLE(stop_long)           AS station_longitude,
    TRY_TO_NUMBER(pax_annual)          AS pax_annual,
    TRY_TO_NUMBER(pax_weekday)         AS pax_weekday,          -- average per weekday
    TRY_TO_NUMBER(pax_norm_weekday)    AS pax_norm_weekday,     -- average per normal (non-holiday) weekday
    TRY_TO_NUMBER(pax_sch_hol_weekday) AS pax_sch_hol_weekday,
    TRY_TO_NUMBER(pax_saturday)        AS pax_saturday,
    TRY_TO_NUMBER(pax_sunday)          AS pax_sunday,
    TRY_TO_NUMBER(pax_pre_am_peak)     AS pax_pre_am_peak,
    TRY_TO_NUMBER(pax_am_peak)         AS pax_am_peak,
    TRY_TO_NUMBER(pax_interpeak)       AS pax_interpeak,
    TRY_TO_NUMBER(pax_pm_peak)         AS pax_pm_peak,
    TRY_TO_NUMBER(pax_pm_late)         AS pax_pm_late
FROM RAW.STATION_ENTRIES;

-- -----------------------------------------------------------------------------
-- 3. Calendar: one row per date, 1 Jul 2024 to 31 Dec 2025.
--    The column is renamed calendar_date because DATE is also a type name.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE STAGING.CALENDAR
COMMENT = 'Calendar with Vic public holidays and school holidays, typed'
AS
SELECT
    TRY_TO_DATE(TRIM(date), 'YYYY-MM-DD')  AS calendar_date,
    TRIM(day_of_week)                      AS day_of_week,
    TRY_TO_BOOLEAN(is_weekday)             AS is_weekday,         -- 'True'/'False' -> TRUE/FALSE
    TRY_TO_BOOLEAN(is_public_holiday)      AS is_public_holiday,
    TRIM(holiday_name)                     AS holiday_name,
    TRY_TO_BOOLEAN(is_school_holiday)      AS is_school_holiday,
    TRY_TO_NUMBER(fiscal_month)            AS fiscal_month,       -- 1 = July
    TRIM(fiscal_year)                      AS fiscal_year
FROM RAW.CALENDAR;

-- -----------------------------------------------------------------------------
-- 4. Quick checks. The full data quality checks are in 04_data_quality_checks.sql.
-- -----------------------------------------------------------------------------

-- Row counts: Metro rows expected 14,547,467 (from the Day 1 profile).
SELECT 'PASSENGER_COUNTS' AS table_name, COUNT(*) AS rows_staged, 14547467 AS rows_expected,
       IFF(COUNT(*) = 14547467, 'OK', 'MISMATCH') AS result
FROM STAGING.PASSENGER_COUNTS
UNION ALL
SELECT 'STATION_ENTRIES', COUNT(*), 222, IFF(COUNT(*) = 222, 'OK', 'MISMATCH') FROM STAGING.STATION_ENTRIES
UNION ALL
SELECT 'CALENDAR', COUNT(*), 549, IFF(COUNT(*) = 549, 'OK', 'MISMATCH') FROM STAGING.CALENDAR;

-- Rows and boardings by time band. Unknown should be 13,777 rows.
SELECT time_band,
       COUNT(*)                                            AS row_count,
       SUM(passenger_boardings)                            AS boardings,
       ROUND(100 * RATIO_TO_REPORT(SUM(passenger_boardings)) OVER (), 1) AS pct_of_boardings
FROM STAGING.PASSENGER_COUNTS
GROUP BY time_band
ORDER BY MIN(departure_time_scheduled) NULLS LAST;
