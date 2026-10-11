-- =============================================================================
-- 04_data_quality_checks.sql
-- Seven checks on the RAW and STAGING tables. Read-only: nothing is changed.
-- Run from the repo root:
--     snow sql -c metro -f sql/04_data_quality_checks.sql
--
-- Results and what was done about them are recorded in docs/data_quality_notes.md.
-- Each check prints a small result table. 'result' columns say OK / CHECK so
-- problems stand out.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE METRO_WH;
USE DATABASE METRO_DB;
USE SCHEMA STAGING;

-- =============================================================================
-- CHECK 1: Row counts and failed type casts
-- RAW Metro rows should equal STAGING rows. A failed cast is a value that was
-- present in RAW (not NULL) but became NULL in STAGING because TRY_ couldn't
-- convert it. Counted in one pass over RAW with COUNT_IF.
-- =============================================================================
SELECT
    (SELECT COUNT(*) FROM RAW.PASSENGER_COUNTS)                                   AS raw_rows_all_modes,
    (SELECT COUNT(*) FROM RAW.PASSENGER_COUNTS WHERE TRIM(mode) = 'Metro Trains') AS raw_rows_metro,
    (SELECT COUNT(*) FROM STAGING.PASSENGER_COUNTS)                               AS staging_rows,
    IFF(raw_rows_metro = staging_rows, 'OK', 'CHECK')                             AS result;

SELECT
    COUNT_IF(business_date            IS NOT NULL AND TRY_TO_DATE(TRIM(business_date), 'YYYY-MM-DD') IS NULL)           AS bad_business_date,
    COUNT_IF(arrival_time_scheduled   IS NOT NULL AND TRY_TO_TIME(TRIM(arrival_time_scheduled), 'HH24:MI:SS') IS NULL)  AS bad_arrival_time,
    COUNT_IF(departure_time_scheduled IS NOT NULL AND TRY_TO_TIME(TRIM(departure_time_scheduled), 'HH24:MI:SS') IS NULL) AS bad_departure_time,
    COUNT_IF(station_latitude         IS NOT NULL AND TRY_TO_DOUBLE(station_latitude)  IS NULL)  AS bad_latitude,
    COUNT_IF(station_longitude        IS NOT NULL AND TRY_TO_DOUBLE(station_longitude) IS NULL)  AS bad_longitude,
    COUNT_IF(station_chainage         IS NOT NULL AND TRY_TO_NUMBER(station_chainage)  IS NULL)  AS bad_chainage,
    COUNT_IF(stop_sequence_number     IS NOT NULL AND TRY_TO_NUMBER(stop_sequence_number) IS NULL) AS bad_stop_sequence,
    COUNT_IF(passenger_boardings      IS NOT NULL AND TRY_TO_NUMBER(passenger_boardings)  IS NULL) AS bad_boardings,
    COUNT_IF(passenger_alightings     IS NOT NULL AND TRY_TO_NUMBER(passenger_alightings) IS NULL) AS bad_alightings,
    COUNT_IF(passenger_arrival_load   IS NOT NULL AND TRY_TO_NUMBER(passenger_arrival_load)   IS NULL) AS bad_arrival_load,
    COUNT_IF(passenger_departure_load IS NOT NULL AND TRY_TO_NUMBER(passenger_departure_load) IS NULL) AS bad_departure_load,
    IFF(bad_business_date + bad_arrival_time + bad_departure_time + bad_latitude + bad_longitude
        + bad_chainage + bad_stop_sequence + bad_boardings + bad_alightings
        + bad_arrival_load + bad_departure_load = 0, 'OK', 'CHECK')               AS result
FROM RAW.PASSENGER_COUNTS
WHERE TRIM(mode) = 'Metro Trains';

-- =============================================================================
-- CHECK 2: Duplicates
-- The plan's key is (business_date, train_number, station, direction). A train
-- can stop at the same station twice in one trip (e.g. running round the City
-- Loop), so stop_sequence_number is checked as the tie-breaker. The true grain
-- should have zero duplicates.
-- =============================================================================
SELECT 'plan key: date + train + station + direction' AS key_tested,
       COUNT(*) AS duplicate_groups, COALESCE(SUM(n), 0) AS rows_involved
FROM (SELECT COUNT(*) AS n FROM STAGING.PASSENGER_COUNTS
      GROUP BY business_date, train_number, station_name, direction HAVING COUNT(*) > 1)
UNION ALL
SELECT 'plan key + stop_sequence_number',
       COUNT(*), COALESCE(SUM(n), 0)
FROM (SELECT COUNT(*) AS n FROM STAGING.PASSENGER_COUNTS
      GROUP BY business_date, train_number, station_name, direction, stop_sequence_number HAVING COUNT(*) > 1)
UNION ALL
-- HASH(*) turns every column of a row into one number, so identical rows share a hash.
SELECT 'exact duplicate rows (every column)',
       COUNT(*), COALESCE(SUM(n), 0)
FROM (SELECT HASH(*) AS row_hash, COUNT(*) AS n
      FROM STAGING.PASSENGER_COUNTS GROUP BY row_hash HAVING COUNT(*) > 1);

-- =============================================================================
-- CHECK 3: Negative or NULL counts (Metro rows)
-- Day 1 found 18 negative rows, all V/Line, so Metro should show 0.
-- =============================================================================
SELECT
    COUNT_IF(passenger_boardings < 0 OR passenger_alightings < 0
             OR passenger_arrival_load < 0 OR passenger_departure_load < 0)  AS negative_rows,
    COUNT_IF(passenger_boardings IS NULL OR passenger_alightings IS NULL
             OR passenger_arrival_load IS NULL OR passenger_departure_load IS NULL) AS null_rows,
    COUNT_IF(MOD(passenger_boardings, 10) <> 0 OR MOD(passenger_alightings, 10) <> 0
             OR MOD(passenger_arrival_load, 10) <> 0 OR MOD(passenger_departure_load, 10) <> 0) AS not_multiple_of_10,
    IFF(negative_rows = 0 AND null_rows = 0, 'OK', 'CHECK')                  AS result
FROM STAGING.PASSENGER_COUNTS;

-- =============================================================================
-- CHECK 4: Share of all-zero rows by line x month
-- An all-zero row (no boardings, alightings or load) usually means the service
-- had no data source, so the true count is unknown, not zero.
-- One row per line: overall share plus the best and worst month.
-- =============================================================================
WITH by_line_month AS (
    SELECT line_name,
           DATE_TRUNC('month', business_date) AS month_start,
           COUNT(*) AS row_count,
           COUNT_IF(passenger_boardings = 0 AND passenger_alightings = 0
                    AND passenger_arrival_load = 0 AND passenger_departure_load = 0) AS zero_rows
    FROM STAGING.PASSENGER_COUNTS
    GROUP BY 1, 2
)
SELECT line_name,
       SUM(row_count)                                         AS row_count,
       ROUND(100 * SUM(zero_rows) / SUM(row_count), 1)         AS zero_pct,
       ROUND(100 * MIN(zero_rows / row_count), 1)              AS best_month_zero_pct,
       ROUND(100 * MAX(zero_rows / row_count), 1)              AS worst_month_zero_pct,
       MAX_BY(TO_CHAR(month_start, 'Mon YYYY'), zero_rows / row_count) AS worst_month,
       IFF(zero_pct > 10, 'CHECK', 'OK')                       AS result
FROM by_line_month
GROUP BY line_name
ORDER BY zero_pct DESC;

-- =============================================================================
-- CHECK 5: Calendar gaps, extra dates and day type agreement
-- (a) every business date in the data should be in the calendar, and every
--     FY2024-25 calendar date should appear in the data;
-- (b) the source's Day_of_Week should match the calendar;
-- (c) the source's Day_Type compared with a day type built from calendar.csv.
-- =============================================================================
WITH data_dates AS (
    SELECT DISTINCT business_date, day_of_week, day_type FROM STAGING.PASSENGER_COUNTS
),
fy_calendar AS (
    SELECT * FROM STAGING.CALENDAR WHERE fiscal_year = 'FY24-25'
)
SELECT
    (SELECT COUNT(*) FROM data_dates)                                                  AS data_dates,
    (SELECT COUNT(*) FROM fy_calendar)                                                 AS calendar_dates_fy24_25,
    (SELECT COUNT(*) FROM data_dates d LEFT JOIN STAGING.CALENDAR c
         ON c.calendar_date = d.business_date WHERE c.calendar_date IS NULL)          AS data_dates_missing_from_calendar,
    (SELECT COUNT(*) FROM fy_calendar c LEFT JOIN data_dates d
         ON d.business_date = c.calendar_date WHERE d.business_date IS NULL)          AS calendar_dates_missing_from_data,
    (SELECT COUNT(*) FROM data_dates d JOIN STAGING.CALENDAR c
         ON c.calendar_date = d.business_date WHERE d.day_of_week <> c.day_of_week)  AS day_of_week_mismatches,
    (SELECT COUNT(*) FROM (SELECT business_date FROM data_dates
                           GROUP BY business_date HAVING COUNT(*) > 1))               AS dates_with_two_day_types,
    IFF(data_dates_missing_from_calendar = 0 AND calendar_dates_missing_from_data = 0
        AND day_of_week_mismatches = 0 AND dates_with_two_day_types = 0, 'OK', 'CHECK') AS result;

-- (c) Day type cross-tab: rows = source Day_Type, columns = calendar-derived type.
--     Anything off the diagonal is a date where the two disagree.
WITH data_dates AS (
    SELECT DISTINCT business_date, day_type FROM STAGING.PASSENGER_COUNTS
),
calendar_type AS (
    SELECT calendar_date,
           CASE WHEN is_public_holiday        THEN 'Public Holiday'
                WHEN day_of_week = 'Saturday' THEN 'Saturday'
                WHEN day_of_week = 'Sunday'   THEN 'Sunday'
                WHEN is_school_holiday        THEN 'School Holiday'
                ELSE                               'Normal Weekday'
           END AS calendar_day_type
    FROM STAGING.CALENDAR
)
SELECT d.day_type AS source_day_type,
       c.calendar_day_type,
       COUNT(*) AS dates,
       IFF(d.day_type = c.calendar_day_type, 'agree', 'DISAGREE') AS result,
       IFF(d.day_type <> c.calendar_day_type,
           LISTAGG(TO_CHAR(d.business_date, 'DD Mon YYYY'), ', ') WITHIN GROUP (ORDER BY d.business_date),
           NULL) AS disagreeing_dates
FROM data_dates d
JOIN calendar_type c ON c.calendar_date = d.business_date
GROUP BY 1, 2
ORDER BY result, source_day_type;

-- =============================================================================
-- CHECK 6: Load continuity
-- (a) Within a stop: arrival load + boardings - alightings should equal the
--     departure load. Each of the four values is rounded to a multiple of 10
--     separately, so small gaps are expected from rounding alone.
-- (b) Between stops: the departure load at one stop should equal the arrival
--     load at the next stop of the same service. LAG() looks one row back
--     within each service, ordered by stop sequence.
-- =============================================================================
SELECT
    'within stop: arrival + boardings - alightings vs departure' AS test,
    COUNT(*)                                                     AS rows_tested,
    COUNT_IF(gap = 0)                                            AS exact,
    COUNT_IF(ABS(gap) BETWEEN 1 AND 20)                          AS gap_up_to_20,
    COUNT_IF(ABS(gap) > 20)                                      AS gap_over_20,
    ROUND(100 * COUNT_IF(ABS(gap) > 20) / COUNT(*), 3)           AS pct_over_20,
    MAX(ABS(gap))                                                AS max_gap
FROM (
    SELECT passenger_arrival_load + passenger_boardings - passenger_alightings
           - passenger_departure_load AS gap
    FROM STAGING.PASSENGER_COUNTS
);

WITH stops AS (
    SELECT passenger_arrival_load,
           LAG(passenger_departure_load) OVER (
               PARTITION BY business_date, train_number, line_name, direction
               ORDER BY stop_sequence_number) AS prev_departure_load
    FROM STAGING.PASSENGER_COUNTS
)
SELECT
    'between stops: previous departure vs next arrival'  AS test,
    COUNT(*)                                              AS rows_tested,
    COUNT_IF(gap = 0)                                     AS exact,
    COUNT_IF(ABS(gap) BETWEEN 1 AND 20)                   AS gap_up_to_20,
    COUNT_IF(ABS(gap) > 20)                               AS gap_over_20,
    ROUND(100 * COUNT_IF(ABS(gap) > 20) / COUNT(*), 3)    AS pct_over_20,
    MAX(ABS(gap))                                         AS max_gap
FROM (SELECT passenger_arrival_load - prev_departure_load AS gap
      FROM stops WHERE prev_departure_load IS NOT NULL);

-- =============================================================================
-- CHECK 7: Station totals vs station entries
-- Raw totals won't match: boardings count every train a passenger takes
-- (including transfers), while entries count barrier entries plus a 5% uplift.
-- So this compares each station's SHARE of the network and its RANK.
-- A share gap over 10% (relative) is flagged; busy interchanges are expected
-- to show more boardings than entries because of transfers.
-- A temporary table lasts only for this session, so it doesn't clutter the database.
-- =============================================================================
CREATE OR REPLACE TEMPORARY TABLE STATION_RECONCILIATION AS
WITH boardings AS (
    SELECT station_name, SUM(passenger_boardings) AS annual_boardings
    FROM STAGING.PASSENGER_COUNTS
    GROUP BY station_name
),
-- Stations V/Line also stops at. Their barrier entries include V/Line
-- passengers, but STAGING only has Metro boardings, so they should run low.
vline_stations AS (
    SELECT DISTINCT TRIM(station_name) AS station_name
    FROM RAW.PASSENGER_COUNTS
    WHERE TRIM(mode) = 'V/Line'
),
joined AS (
    SELECT COALESCE(b.station_name, e.station_name) AS station_name,
           b.annual_boardings,
           e.pax_annual                              AS annual_entries
    FROM boardings b
    FULL OUTER JOIN STAGING.STATION_ENTRIES e ON e.station_name = b.station_name
)
SELECT station_name,
       station_name IN (SELECT station_name FROM vline_stations) AS has_vline,
       annual_boardings,
       annual_entries,
       ROUND(100 * annual_boardings / SUM(annual_boardings) OVER (), 3) AS boardings_share_pct,
       ROUND(100 * annual_entries   / SUM(annual_entries)   OVER (), 3) AS entries_share_pct,
       ROUND(100 * (boardings_share_pct - entries_share_pct) / NULLIF(entries_share_pct, 0), 1) AS share_diff_pct,
       RANK() OVER (ORDER BY annual_boardings DESC NULLS LAST) AS boardings_rank,
       RANK() OVER (ORDER BY annual_entries   DESC NULLS LAST) AS entries_rank
FROM joined;

-- Summary: name matching, rank correlation and how many stations are flagged.
-- CORR on the two ranks is Spearman's rank correlation (1 = identical order).
SELECT
    COUNT(*)                                                       AS stations,
    COUNT_IF(annual_boardings IS NULL)                             AS only_in_entries,
    COUNT_IF(annual_entries IS NULL)                               AS only_in_passenger_counts,
    ROUND(CORR(boardings_rank, entries_rank), 3)                   AS rank_correlation,
    COUNT_IF(ABS(share_diff_pct) > 10)                             AS stations_share_diff_over_10pct,
    ROUND(100 * COUNT_IF(ABS(share_diff_pct) > 10) / COUNT(*), 1)  AS pct_stations_flagged
FROM STATION_RECONCILIATION;

-- Why so many are flagged: interchange transfers inflate the boardings total,
-- which shrinks every other station's share. Ratio = boardings / entries per
-- station; network-wide it is about 1.26. Grouped by whether V/Line stops there.
SELECT
    IFF(has_vline, 'V/Line also stops here', 'Metro only')               AS station_group,
    COUNT(*)                                                              AS stations,
    ROUND(SUM(annual_boardings) / SUM(annual_entries), 2)                 AS boardings_per_entry,
    ROUND(MEDIAN(annual_boardings / annual_entries), 2)                   AS median_station_ratio,
    ROUND(MEDIAN(share_diff_pct), 1)                                      AS median_share_diff_pct,
    COUNT_IF(share_diff_pct BETWEEN -10 AND 10)                           AS within_10pct,
    COUNT_IF(ABS(share_diff_pct) > 10 AND ABS(share_diff_pct) <= 25)      AS diff_10_to_25pct,
    COUNT_IF(ABS(share_diff_pct) > 25)                                    AS diff_over_25pct
FROM STATION_RECONCILIATION
GROUP BY 1
ORDER BY 1;

-- Any station names that didn't match between the two files.
SELECT station_name, annual_boardings, annual_entries
FROM STATION_RECONCILIATION
WHERE annual_boardings IS NULL OR annual_entries IS NULL
ORDER BY station_name;

-- The 15 biggest share differences, to see whether they are interchanges.
SELECT station_name, has_vline, annual_boardings, annual_entries,
       boardings_share_pct, entries_share_pct, share_diff_pct,
       boardings_rank, entries_rank
FROM STATION_RECONCILIATION
WHERE annual_boardings IS NOT NULL AND annual_entries IS NOT NULL
ORDER BY ABS(share_diff_pct) DESC
LIMIT 15;

-- Top 10 stations by entries: do the two sources agree on the busiest stations?
SELECT station_name, has_vline, entries_rank, boardings_rank, entries_share_pct, boardings_share_pct, share_diff_pct
FROM STATION_RECONCILIATION
ORDER BY entries_rank
LIMIT 10;
