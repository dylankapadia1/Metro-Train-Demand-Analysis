-- =============================================================================
-- 06_analysis.sql
-- Answers the seven analysis questions from the build plan, using the MART tables.
-- Read-only. Run from the repo root:
--     snow sql -c metro -f sql/06_analysis.sql
--
-- Findings, one sentence each, are written up in docs/analysis_findings.md.
--
-- Reading the numbers:
--   * Boardings are DTP's modelled estimates, rounded to multiples of 10.
--   * A boarding is one passenger getting on one train, so a trip with a change
--     of trains counts twice. Transfer hubs (Flinders Street, Richmond, North
--     Melbourne) look bigger here than in barrier entries.
--   * "Weekday" means a normal weekday, not a public holiday or school holiday
--     (199 days), unless a query says otherwise.
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE METRO_WH;
USE DATABASE METRO_DB;
USE SCHEMA MART;

-- =============================================================================
-- Q1. Top 10 stations by weekday boardings, and their share of the network.
-- =============================================================================
SELECT
    network_rank,
    station_name,
    avg_daily_boardings,
    ROUND(100 * total_boardings / SUM(total_boardings) OVER (), 1)  AS share_of_network_pct,
    -- Running total: how much of the network the top N stations make up.
    ROUND(100 * SUM(total_boardings) OVER (ORDER BY network_rank)
              / SUM(total_boardings) OVER (), 1)                    AS cumulative_share_pct,
    am_peak_share_pct,
    is_transfer_hub,
    lines_served
FROM MART.STATION_SUMMARY
WHERE day_type = 'Normal Weekday'
QUALIFY network_rank <= 10
ORDER BY network_rank;

-- Same top 10, but ranked on barrier entries (counts each passenger once).
-- Shows how much the transfer hubs move when transfers aren't counted.
SELECT
    RANK() OVER (ORDER BY annual_entries DESC)                       AS entries_rank,
    station_name,
    annual_entries,
    ROUND(100 * annual_entries / SUM(annual_entries) OVER (), 1)    AS share_of_entries_pct,
    network_rank                                                     AS weekday_boardings_rank,
    boardings_per_entry
FROM MART.STATION_SUMMARY
WHERE day_type = 'Normal Weekday'
QUALIFY entries_rank <= 10
ORDER BY entries_rank;

-- =============================================================================
-- Q2. Which line has the most weekday AM peak boardings, and which carries
--     the heaviest loads? Corridor lines only.
-- =============================================================================
WITH am_peak AS (
    SELECT d.line_name,
           AVG(d.boardings)            AS avg_am_peak_boardings,
           AVG(d.max_departure_load)   AS avg_max_am_peak_load,
           AVG(d.services)             AS avg_am_peak_services
    FROM MART.DAILY_LINE_DEMAND d
    JOIN MART.DIM_LINE l ON l.line_name = d.line_name AND l.is_corridor_line
    WHERE d.day_type = 'Normal Weekday' AND d.time_band = 'AM Peak'
    GROUP BY d.line_name
),
regular_loads AS (
    -- Average peak load of each line's regular services that peak in the AM peak.
    SELECT line_name,
           ROUND(AVG(avg_peak_load))   AS avg_service_peak_load,
           MAX(avg_peak_load)          AS busiest_service_peak_load
    FROM MART.PEAK_LOAD_SERVICES
    WHERE is_regular_service AND usual_peak_time_band = 'AM Peak'
    GROUP BY line_name
)
SELECT
    RANK() OVER (ORDER BY a.avg_am_peak_boardings DESC)              AS boardings_rank,
    a.line_name,
    ROUND(a.avg_am_peak_boardings)                                   AS avg_am_peak_boardings,
    ROUND(100 * a.avg_am_peak_boardings / SUM(a.avg_am_peak_boardings) OVER (), 1) AS share_of_am_peak_pct,
    ROUND(a.avg_am_peak_services)                                    AS avg_am_peak_services,
    ROUND(a.avg_am_peak_boardings / a.avg_am_peak_services)          AS boardings_per_service,
    r.avg_service_peak_load,
    r.busiest_service_peak_load,
    RANK() OVER (ORDER BY r.avg_service_peak_load DESC NULLS LAST)  AS load_rank,
    l.data_caveat
FROM am_peak a
LEFT JOIN regular_loads r USING (line_name)
JOIN MART.DIM_LINE l USING (line_name)
ORDER BY boardings_rank;

-- =============================================================================
-- Q3. How much quieter are weekends and holidays than a normal weekday?
--     Network total per day, averaged within each day type.
-- =============================================================================
WITH daily_network AS (
    SELECT business_date, day_type, SUM(boardings) AS boardings
    FROM MART.DAILY_LINE_DEMAND
    GROUP BY business_date, day_type
),
by_day_type AS (
    SELECT day_type,
           COUNT(*)              AS days,
           ROUND(AVG(boardings)) AS avg_daily_boardings
    FROM daily_network
    GROUP BY day_type
)
SELECT
    day_type,
    days,
    avg_daily_boardings,
    ROUND(100 * (avg_daily_boardings
                 / MAX(IFF(day_type = 'Normal Weekday', avg_daily_boardings, NULL)) OVER () - 1), 1)
                                                                    AS vs_normal_weekday_pct
FROM by_day_type
ORDER BY avg_daily_boardings DESC;

-- Same comparison for the AM peak only: holidays hit commuting hardest.
WITH daily_am AS (
    SELECT business_date, day_type, SUM(boardings) AS boardings
    FROM MART.DAILY_LINE_DEMAND
    WHERE time_band = 'AM Peak'
    GROUP BY business_date, day_type
)
SELECT
    day_type,
    ROUND(AVG(boardings))                                            AS avg_am_peak_boardings,
    ROUND(100 * (AVG(boardings)
                 / MAX(IFF(day_type = 'Normal Weekday', AVG(boardings), NULL)) OVER () - 1), 1)
                                                                    AS vs_normal_weekday_pct
FROM daily_am
GROUP BY day_type
ORDER BY avg_am_peak_boardings DESC;

-- =============================================================================
-- Q4. Weekday demand by day of week: is there a Tuesday-Thursday peak
--     (hybrid work)? Normal weekdays only, so holidays don't skew a day.
-- =============================================================================
WITH daily AS (
    SELECT d.business_date,
           c.day_of_week,
           c.day_of_week_num,
           SUM(d.boardings)                                    AS boardings,
           SUM(IFF(d.time_band = 'AM Peak', d.boardings, 0))   AS am_peak_boardings
    FROM MART.DAILY_LINE_DEMAND d
    JOIN MART.DIM_CALENDAR c ON c.calendar_date = d.business_date
    WHERE d.day_type = 'Normal Weekday'
    GROUP BY 1, 2, 3
)
SELECT
    day_of_week,
    COUNT(*)                                                         AS days,
    ROUND(AVG(boardings))                                            AS avg_daily_boardings,
    -- Index: 100 = the average normal weekday.
    ROUND(100 * AVG(boardings) / AVG(AVG(boardings)) OVER (), 1)    AS daily_index,
    ROUND(AVG(am_peak_boardings))                                    AS avg_am_peak_boardings,
    ROUND(100 * AVG(am_peak_boardings) / AVG(AVG(am_peak_boardings)) OVER (), 1) AS am_peak_index
FROM daily
GROUP BY day_of_week, day_of_week_num
ORDER BY day_of_week_num;

-- =============================================================================
-- Q5. Monthly trend across FY2024-25.
--     Average per normal weekday (so short months and holiday-heavy months
--     like January don't look artificially quiet), plus the all-days average.
-- =============================================================================
WITH daily AS (
    SELECT d.business_date, c.month_start, c.month_label, d.day_type,
           SUM(d.boardings) AS boardings
    FROM MART.DAILY_LINE_DEMAND d
    JOIN MART.DIM_CALENDAR c ON c.calendar_date = d.business_date
    GROUP BY 1, 2, 3, 4
)
SELECT
    month_label,
    COUNT_IF(day_type = 'Normal Weekday')                                   AS normal_weekdays,
    ROUND(AVG(IFF(day_type = 'Normal Weekday', boardings, NULL)))          AS avg_normal_weekday_boardings,
    ROUND(100 * AVG(IFF(day_type = 'Normal Weekday', boardings, NULL))
              / AVG(AVG(IFF(day_type = 'Normal Weekday', boardings, NULL))) OVER (), 1)
                                                                           AS weekday_index,
    ROUND(AVG(boardings))                                                  AS avg_all_days_boardings,
    SUM(boardings)                                                         AS month_total_boardings
FROM daily
GROUP BY month_start, month_label
ORDER BY month_start;

-- Q5b. March 2025 stands out (+16% vs the average weekday). Is it a few event
--      days or the whole month, and is it every line? Compares each line's
--      average normal weekday in March with February and May together.
WITH daily_line AS (
    SELECT business_date, line_name, SUM(boardings) AS boardings
    FROM MART.DAILY_LINE_DEMAND
    WHERE day_type = 'Normal Weekday'
    GROUP BY 1, 2
)
SELECT d.line_name,
       ROUND(AVG(IFF(MONTH(business_date) = 3, boardings, NULL)))      AS avg_march,
       ROUND(AVG(IFF(MONTH(business_date) IN (2, 5), boardings, NULL))) AS avg_feb_and_may,
       ROUND(100 * (avg_march / avg_feb_and_may - 1), 1)                AS march_uplift_pct
FROM daily_line d
JOIN MART.DIM_LINE l ON l.line_name = d.line_name AND l.include_in_forecast
GROUP BY d.line_name
ORDER BY march_uplift_pct DESC;

-- =============================================================================
-- Q6. Top 10 regular services by peak load, with where and when they peak.
--     The source model has no capacity limit: read high loads as "very
--     crowded", not exact counts.
-- =============================================================================
SELECT
    load_rank,
    line_name,
    IFF(direction = 'U', 'to city', 'from city')     AS direction,
    train_number,
    TO_CHAR(usual_first_departure, 'HH24:MI')        AS departs,
    origin_station || ' to ' || destination_station  AS route,
    usual_peak_station,
    TO_CHAR(usual_peak_time, 'HH24:MI')              AS peak_time,
    avg_peak_load,
    max_peak_load,
    weekdays_run
FROM MART.PEAK_LOAD_SERVICES
WHERE load_rank <= 10
ORDER BY load_rank;

-- Where do the top 50 regular services peak? Concentration by station.
SELECT usual_peak_station,
       COUNT(*)                     AS services_in_top_50,
       LISTAGG(DISTINCT line_name, ', ') WITHIN GROUP (ORDER BY line_name) AS lines
FROM MART.PEAK_LOAD_SERVICES
WHERE load_rank <= 50
GROUP BY usual_peak_station
ORDER BY services_in_top_50 DESC
LIMIT 8;

-- =============================================================================
-- Q7. Window functions.
-- (a) RANK() OVER (PARTITION BY line ...): the 3 busiest stations on each
--     corridor line. PARTITION BY restarts the ranking for every line;
--     QUALIFY filters on the window result, like HAVING does for GROUP BY.
--     City stations are excluded so each line shows its own suburban stations.
-- =============================================================================
WITH line_station AS (
    SELECT p.line_name,
           p.station_name,
           SUM(p.passenger_boardings) / 199 AS avg_weekday_boardings   -- 199 normal weekdays
    FROM STAGING.PASSENGER_COUNTS p
    JOIN MART.DIM_LINE l ON l.line_name = p.line_name AND l.include_in_forecast
    WHERE p.day_type = 'Normal Weekday'
      AND p.station_name NOT IN ('Flinders Street', 'Southern Cross', 'Flagstaff',
                                 'Melbourne Central', 'Parliament', 'Richmond', 'North Melbourne')
    GROUP BY 1, 2
)
SELECT line_name,
       RANK() OVER (PARTITION BY line_name ORDER BY avg_weekday_boardings DESC) AS rank_on_line,
       station_name,
       ROUND(avg_weekday_boardings)                                            AS avg_weekday_boardings
FROM line_station
QUALIFY rank_on_line <= 3
ORDER BY line_name, rank_on_line;

-- =============================================================================
-- (b) AVG() OVER (ORDER BY date ROWS 6 PRECEDING): 7-day moving average of
--     network boardings. Each day averages itself and the 6 days before it,
--     which smooths out the weekday/weekend cycle and shows the underlying
--     level. Output: the 5 highest and 5 lowest 7-day windows.
-- =============================================================================
WITH daily_network AS (
    SELECT business_date, SUM(boardings) AS boardings
    FROM MART.DAILY_LINE_DEMAND
    GROUP BY business_date
),
moving AS (
    SELECT business_date,
           boardings,
           AVG(boardings) OVER (ORDER BY business_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS boardings_7d_avg,
           COUNT(*)       OVER (ORDER BY business_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS days_in_window
    FROM daily_network
)
SELECT *
FROM (
    SELECT 'highest' AS which,
           TO_CHAR(DATEADD(day, -6, business_date), 'DD Mon') || ' to ' || TO_CHAR(business_date, 'DD Mon YYYY') AS week,
           ROUND(boardings_7d_avg) AS boardings_7d_avg
    FROM moving WHERE days_in_window = 7
    QUALIFY ROW_NUMBER() OVER (ORDER BY boardings_7d_avg DESC) <= 5
    UNION ALL
    SELECT 'lowest',
           TO_CHAR(DATEADD(day, -6, business_date), 'DD Mon') || ' to ' || TO_CHAR(business_date, 'DD Mon YYYY'),
           ROUND(boardings_7d_avg)
    FROM moving WHERE days_in_window = 7
    QUALIFY ROW_NUMBER() OVER (ORDER BY boardings_7d_avg ASC) <= 5
)
ORDER BY which, boardings_7d_avg DESC;
