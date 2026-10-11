-- =============================================================================
-- 01_setup.sql
-- Creates the warehouse, database and schemas for the project.
-- Run once in a Snowflake worksheet after starting the trial.
--
-- Layers:
--   RAW      data exactly as it arrives from the CSVs (every column VARCHAR)
--   STAGING  cleaned and typed: casts, trimmed names, Metro Trains only, time bands
--   MART     analysis-ready tables that feed the forecast and Power BI
-- Keeping the layers apart means any problem can be traced back to the raw file.
-- =============================================================================

-- SYSADMIN is Snowflake's standard role for creating warehouses and databases.
-- (ACCOUNTADMIN works too, but it's best practice not to build objects with it.)
USE ROLE SYSADMIN;

-- A warehouse is the compute that runs queries. X-Small is the cheapest size.
-- AUTO_SUSPEND = 60 stops it after 60 idle seconds so it doesn't burn trial credits;
-- AUTO_RESUME restarts it automatically when the next query runs.
CREATE WAREHOUSE IF NOT EXISTS METRO_WH
    WAREHOUSE_SIZE      = 'XSMALL'
    AUTO_SUSPEND        = 60
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Metro train demand portfolio project';

CREATE DATABASE IF NOT EXISTS METRO_DB
    COMMENT = 'Melbourne metro train demand: DataVic passenger counts FY2024-25';

CREATE SCHEMA IF NOT EXISTS METRO_DB.RAW     COMMENT = 'Source files loaded as-is, all VARCHAR';
CREATE SCHEMA IF NOT EXISTS METRO_DB.STAGING COMMENT = 'Typed, cleaned, Metro Trains only';
CREATE SCHEMA IF NOT EXISTS METRO_DB.MART    COMMENT = 'Analysis tables for forecasting and Power BI';

-- Set the session context so later scripts don't need fully qualified names.
USE WAREHOUSE METRO_WH;
USE DATABASE METRO_DB;
USE SCHEMA RAW;

-- Check: should list RAW, STAGING and MART (plus Snowflake's built-in schemas).
SHOW SCHEMAS IN DATABASE METRO_DB;
