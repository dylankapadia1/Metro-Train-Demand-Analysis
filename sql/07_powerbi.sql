-- =============================================================================
-- 07_powerbi.sql
-- Small lookup (dimension) tables for the Power BI model, built from the marts.
-- Run from the repo root after 05_marts.sql and the forecast notebook:
--     snow sql -c metro -f sql/07_powerbi.sql
--
-- Why these exist:
--   * DIM_DAY_TYPE lets one day-type slicer filter every page, sorts day types
--     in a sensible order (not alphabetically), and holds the number of days of
--     each type, so "average per day" is right for any mix of selected types.
--   * DIM_TIME_BAND sorts time bands Early -> Evening.
--   * DIM_STATION is one row per station for the map and the station slicer.
--
-- Safe to re-run: every table is CREATE OR REPLACE.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE METRO_WH;
USE DATABASE METRO_DB;
USE SCHEMA MART;

-- -----------------------------------------------------------------------------
-- 1. DIM_DAY_TYPE: the five day types, in display order.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE MART.DIM_DAY_TYPE
COMMENT = 'Day types for Power BI: display order and number of FY2024-25 days of each type'
AS
SELECT
    t.day_type,
    t.sort_order,
    t.day_group,
    COUNT(c.calendar_date) AS days_in_data      -- e.g. 199 normal weekdays
FROM (
    SELECT column1 AS day_type, column2 AS sort_order, column3 AS day_group
    FROM VALUES ('Normal Weekday', 1, 'Weekday'),
                ('School Holiday', 2, 'Weekday'),
                ('Saturday',       3, 'Weekend'),
                ('Sunday',         4, 'Weekend'),
                ('Public Holiday', 5, 'Holiday')
) t
LEFT JOIN MART.DIM_CALENDAR c
       ON c.day_type = t.day_type AND c.has_passenger_data
GROUP BY t.day_type, t.sort_order, t.day_group;

-- -----------------------------------------------------------------------------
-- 2. DIM_TIME_BAND: the six time bands, in time order (same bands as 03_staging.sql).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE MART.DIM_TIME_BAND
COMMENT = 'Time bands for Power BI, in time order'
AS
SELECT column1 AS time_band, column2 AS sort_order, column3 AS hours
FROM VALUES ('Early',      1, 'before 07:00'),
            ('AM Peak',    2, '07:00-08:59'),
            ('Inter-peak', 3, '09:00-15:59'),
            ('PM Peak',    4, '16:00-18:59'),
            ('Evening',    5, '19:00 onwards'),
            ('Unknown',    6, 'no scheduled time');

-- -----------------------------------------------------------------------------
-- 3. DIM_STATION: one row per station. STATION_SUMMARY has one row per station
--    per day type; the station-level columns are the same on every row, so
--    ANY_VALUE picks them up. Normal-weekday figures added for tooltips.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE MART.DIM_STATION
COMMENT = 'One row per station: location, lines served, reconciliation flags, normal-weekday boardings and rank'
AS
SELECT
    station_name,
    ANY_VALUE(lines_served)           AS lines_served,
    ANY_VALUE(station_latitude)       AS station_latitude,
    ANY_VALUE(station_longitude)      AS station_longitude,
    ANY_VALUE(annual_boardings)       AS annual_boardings,
    ANY_VALUE(annual_entries)         AS annual_entries,
    ANY_VALUE(boardings_per_entry)    AS boardings_per_entry,
    ANY_VALUE(is_transfer_hub)        AS is_transfer_hub,
    ANY_VALUE(has_vline)              AS has_vline,
    MAX(IFF(day_type = 'Normal Weekday', avg_daily_boardings, NULL)) AS normal_weekday_boardings,
    MAX(IFF(day_type = 'Normal Weekday', network_rank, NULL))        AS normal_weekday_rank
FROM MART.STATION_SUMMARY
GROUP BY station_name;

-- -----------------------------------------------------------------------------
-- 4. Checks.
-- -----------------------------------------------------------------------------
SELECT 'DIM_DAY_TYPE' AS table_name, COUNT(*) AS row_count, SUM(days_in_data) AS days, 365 AS expected_days,
       IFF(COUNT(*) = 5 AND SUM(days_in_data) = 365, 'OK', 'CHECK') AS result
FROM MART.DIM_DAY_TYPE
UNION ALL
SELECT 'DIM_TIME_BAND', COUNT(*), NULL, NULL, IFF(COUNT(*) = 6, 'OK', 'CHECK') FROM MART.DIM_TIME_BAND
UNION ALL
SELECT 'DIM_STATION', COUNT(*), NULL, NULL, IFF(COUNT(*) = 222, 'OK', 'CHECK') FROM MART.DIM_STATION;

SELECT * FROM MART.DIM_DAY_TYPE ORDER BY sort_order;

-- Every day type and time band used in the facts must exist in the lookup tables,
-- or those rows would drop out of filtered visuals in Power BI.
SELECT 'day types missing from DIM_DAY_TYPE' AS test, COUNT(*) AS missing
FROM (SELECT DISTINCT day_type FROM MART.DAILY_LINE_DEMAND
      UNION SELECT DISTINCT day_type FROM MART.STATION_SUMMARY
      UNION SELECT DISTINCT day_type FROM MART.HOURLY_PROFILE) f
WHERE f.day_type NOT IN (SELECT day_type FROM MART.DIM_DAY_TYPE)
UNION ALL
SELECT 'time bands missing from DIM_TIME_BAND', COUNT(*)
FROM (SELECT DISTINCT time_band FROM MART.DAILY_LINE_DEMAND
      UNION SELECT DISTINCT time_band FROM MART.HOURLY_PROFILE) f
WHERE f.time_band NOT IN (SELECT time_band FROM MART.DIM_TIME_BAND)
UNION ALL
SELECT 'stations missing from DIM_STATION (peak-load services)', COUNT(*)
FROM (SELECT DISTINCT usual_peak_station AS s FROM MART.PEAK_LOAD_SERVICES) f
WHERE f.s NOT IN (SELECT station_name FROM MART.DIM_STATION);
