-- =============================================================================
-- 02_load_raw.sql
-- Uploads the four source CSVs to Snowflake and loads them into RAW tables.
-- Run from the repo root with Snowflake CLI (PUT doesn't work in Snowsight):
--     snow sql -c metro -f sql/02_load_raw.sql
--
-- RAW rule: every column is VARCHAR (text), exactly as it appears in the file.
-- Nothing is cast or cleaned here, so a load never fails on a bad value and
-- the original data is always there to compare against. 03_staging.sql does
-- the typing and cleaning.
--
-- Safe to re-run: PUT skips files already in the stage, and CREATE OR REPLACE
-- TABLE starts each table empty, so nothing is loaded twice.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE METRO_WH;
USE DATABASE METRO_DB;
USE SCHEMA RAW;

-- -----------------------------------------------------------------------------
-- 1. File format: tells Snowflake how to read the CSVs.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FILE FORMAT RAW.CSV_FORMAT
    TYPE                         = CSV
    SKIP_HEADER                  = 1        -- first row is column names
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'      -- values containing commas are quoted
    EMPTY_FIELD_AS_NULL          = TRUE     -- blank cells become NULL, not ''
    NULL_IF                      = ('')
    SKIP_BYTE_ORDER_MARK         = TRUE     -- station entries file starts with a BOM
    ENCODING                     = 'UTF8'
    COMMENT = 'Comma-separated, one header row, optional double quotes';

-- -----------------------------------------------------------------------------
-- 2. Internal stage: file storage inside Snowflake. Each file goes in its own
--    folder so each COPY INTO picks up only the file it's meant to.
-- -----------------------------------------------------------------------------
CREATE STAGE IF NOT EXISTS RAW.SOURCE_STAGE
    FILE_FORMAT = RAW.CSV_FORMAT
    COMMENT = 'Uploaded source CSVs (DataVic + self-built calendar)';

-- -----------------------------------------------------------------------------
-- 3. Upload. PUT gzips each file on this machine before sending it, so the
--    2.8 GB file uploads as roughly 0.5 GB. PARALLEL splits it into chunks
--    that upload at the same time.
-- -----------------------------------------------------------------------------
PUT 'file://F:/Personal/Career/Portfolio/Metro-Train-Demand-Analysis/data/raw/train_service_passenger_counts_fy_2024_2025.csv'
    @RAW.SOURCE_STAGE/passenger_counts/
    AUTO_COMPRESS = TRUE PARALLEL = 8;

PUT 'file://F:/Personal/Career/Portfolio/Metro-Train-Demand-Analysis/data/raw/annual_metropolitan_train_station_entries_fy_2024_2025.csv'
    @RAW.SOURCE_STAGE/station_entries/
    AUTO_COMPRESS = TRUE;

PUT 'file://F:/Personal/Career/Portfolio/Metro-Train-Demand-Analysis/data/raw/monthly_average_patronage_by_day_type_and_by_mode.csv'
    @RAW.SOURCE_STAGE/monthly_patronage/
    AUTO_COMPRESS = TRUE;

PUT 'file://F:/Personal/Career/Portfolio/Metro-Train-Demand-Analysis/data/reference/calendar.csv'
    @RAW.SOURCE_STAGE/calendar/
    AUTO_COMPRESS = TRUE OVERWRITE = TRUE;  -- small file we regenerate, so always refresh

-- Check: should list four .gz files.
LIST @RAW.SOURCE_STAGE;

-- -----------------------------------------------------------------------------
-- 4. RAW tables. Column names match the CSV headers exactly.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE RAW.PASSENGER_COUNTS (
    BUSINESS_DATE             VARCHAR,
    DAY_OF_WEEK               VARCHAR,
    DAY_TYPE                  VARCHAR,
    MODE                      VARCHAR,
    TRAIN_NUMBER              VARCHAR,
    LINE_NAME                 VARCHAR,
    "GROUP"                   VARCHAR,  -- GROUP is a reserved word, so it must be quoted
    DIRECTION                 VARCHAR,
    ORIGIN_STATION            VARCHAR,
    DESTINATION_STATION       VARCHAR,
    STATION_NAME              VARCHAR,
    STATION_LATITUDE          VARCHAR,
    STATION_LONGITUDE         VARCHAR,
    STATION_CHAINAGE          VARCHAR,
    STOP_SEQUENCE_NUMBER      VARCHAR,
    ARRIVAL_TIME_SCHEDULED    VARCHAR,
    DEPARTURE_TIME_SCHEDULED  VARCHAR,
    PASSENGER_BOARDINGS       VARCHAR,
    PASSENGER_ALIGHTINGS      VARCHAR,
    PASSENGER_ARRIVAL_LOAD    VARCHAR,
    PASSENGER_DEPARTURE_LOAD  VARCHAR
)
COMMENT = 'DataVic Train Service Passenger Counts FY2024-25, as loaded (all VARCHAR)';

CREATE OR REPLACE TABLE RAW.STATION_ENTRIES (
    FIN_YEAR             VARCHAR,
    STOP_ID              VARCHAR,
    STOP_NAME            VARCHAR,
    STOP_LAT             VARCHAR,
    STOP_LONG            VARCHAR,
    PAX_ANNUAL           VARCHAR,
    PAX_WEEKDAY          VARCHAR,
    PAX_NORM_WEEKDAY     VARCHAR,
    PAX_SCH_HOL_WEEKDAY  VARCHAR,
    PAX_SATURDAY         VARCHAR,
    PAX_SUNDAY           VARCHAR,
    PAX_PRE_AM_PEAK      VARCHAR,
    PAX_AM_PEAK          VARCHAR,
    PAX_INTERPEAK        VARCHAR,
    PAX_PM_PEAK          VARCHAR,
    PAX_PM_LATE          VARCHAR
)
COMMENT = 'DataVic annual metropolitan train station entries FY2024-25, as loaded (all VARCHAR)';

-- DTP's official monthly patronage (station entries + 5% uplift, from myki and
-- barrier data). Used to validate the modelled passenger counts (check 8).
CREATE OR REPLACE TABLE RAW.MONTHLY_PATRONAGE (
    YEAR         VARCHAR,
    MONTH        VARCHAR,
    MONTH_NAME   VARCHAR,
    DAY_OF_WEEK  VARCHAR,
    DAY_TYPE     VARCHAR,
    MODE         VARCHAR,
    PAX_DAILY    VARCHAR
)
COMMENT = 'DataVic monthly average patronage by day type and by mode, all modes 2018 onwards, as loaded (all VARCHAR)';

CREATE OR REPLACE TABLE RAW.CALENDAR (
    DATE               VARCHAR,
    DAY_OF_WEEK        VARCHAR,
    IS_WEEKDAY         VARCHAR,
    IS_PUBLIC_HOLIDAY  VARCHAR,
    HOLIDAY_NAME       VARCHAR,
    IS_SCHOOL_HOLIDAY  VARCHAR,
    FISCAL_MONTH       VARCHAR,
    FISCAL_YEAR        VARCHAR
)
COMMENT = 'Self-built calendar (scripts/build_calendar.py), as loaded (all VARCHAR)';

-- -----------------------------------------------------------------------------
-- 5. Load. ON_ERROR = ABORT_STATEMENT stops the whole load at the first bad row,
--    so a partial table never looks like a complete one. The output shows
--    rows_parsed, rows_loaded and errors_seen for each file.
-- -----------------------------------------------------------------------------
COPY INTO RAW.PASSENGER_COUNTS
    FROM @RAW.SOURCE_STAGE/passenger_counts/
    FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FORMAT')
    ON_ERROR = ABORT_STATEMENT;

COPY INTO RAW.STATION_ENTRIES
    FROM @RAW.SOURCE_STAGE/station_entries/
    FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FORMAT')
    ON_ERROR = ABORT_STATEMENT;

COPY INTO RAW.MONTHLY_PATRONAGE
    FROM @RAW.SOURCE_STAGE/monthly_patronage/
    FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FORMAT')
    ON_ERROR = ABORT_STATEMENT;

COPY INTO RAW.CALENDAR
    FROM @RAW.SOURCE_STAGE/calendar/
    FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FORMAT')
    ON_ERROR = ABORT_STATEMENT;

-- -----------------------------------------------------------------------------
-- 6. Check: row counts vs the pandas profile done on Day 1.
-- -----------------------------------------------------------------------------
SELECT 'PASSENGER_COUNTS' AS table_name, COUNT(*) AS rows_loaded, 15937506 AS rows_expected,
       IFF(COUNT(*) = 15937506, 'OK', 'MISMATCH') AS result
FROM RAW.PASSENGER_COUNTS
UNION ALL
SELECT 'STATION_ENTRIES', COUNT(*), 222, IFF(COUNT(*) = 222, 'OK', 'MISMATCH')
FROM RAW.STATION_ENTRIES
UNION ALL
SELECT 'MONTHLY_PATRONAGE', COUNT(*), 4450, IFF(COUNT(*) = 4450, 'OK', 'MISMATCH')
FROM RAW.MONTHLY_PATRONAGE
UNION ALL
SELECT 'CALENDAR', COUNT(*), 549, IFF(COUNT(*) = 549, 'OK', 'MISMATCH')
FROM RAW.CALENDAR;
