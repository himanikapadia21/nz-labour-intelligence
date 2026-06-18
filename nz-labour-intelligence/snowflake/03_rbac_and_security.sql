-- ═══════════════════════════════════════════════════════════════════════════
-- 03_rbac_and_security.sql
-- Demonstrates advanced Snowflake security features.
-- These are what differentiate your project from a basic SQL warehouse demo.
-- Run AFTER initial data has been loaded.
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE NZ_LABOUR_WH;
USE DATABASE NZ_LABOUR_DB;

-- ════════════════════════════════════════════════════════════════════════════
-- 1. DYNAMIC DATA MASKING
-- Hides wage values from REPORTER_ROLE — they see -1 instead of actual wages.
-- ANALYST_ROLE and ENGINEER_ROLE see real values.
-- ════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE MASKING POLICY RAW.WAGE_MASKING_POLICY
    AS (val FLOAT) RETURNS FLOAT ->
    CASE
        WHEN CURRENT_ROLE() IN ('ENGINEER_ROLE', 'ANALYST_ROLE') THEN val
        ELSE -1
    END
    COMMENT = 'Masks raw wage values. Reporters see -1. Analysts and engineers see actuals.';

-- Apply to the wages table
ALTER TABLE RAW.RAW_QES_WAGES
    MODIFY COLUMN DATA_VALUE
    SET MASKING POLICY RAW.WAGE_MASKING_POLICY;

-- ── Test masking ──────────────────────────────────────────────────────────────
-- Run these to verify masking works
USE ROLE ENGINEER_ROLE;
SELECT series_reference, period, data_value FROM RAW.RAW_QES_WAGES LIMIT 5;
-- Expected: real wage values

USE ROLE REPORTER_ROLE;
SELECT series_reference, period, data_value FROM RAW.RAW_QES_WAGES LIMIT 5;
-- Expected: -1 for data_value column

USE ROLE ACCOUNTADMIN;  -- reset

-- ════════════════════════════════════════════════════════════════════════════
-- 2. ROW ACCESS POLICY
-- REPORTER_ROLE can only see rows for national-level data (New Zealand total).
-- ANALYST_ROLE and ENGINEER_ROLE see all regions.
-- ════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE ROW ACCESS POLICY RAW.REGIONAL_ACCESS_POLICY
    AS (series_title_3 VARCHAR) RETURNS BOOLEAN ->
    CASE
        WHEN CURRENT_ROLE() IN ('ENGINEER_ROLE', 'ANALYST_ROLE') THEN TRUE
        WHEN CURRENT_ROLE() = 'REPORTER_ROLE'
            THEN series_title_3 ILIKE '%New Zealand%'
              OR series_title_3 ILIKE '%Total%'
              OR series_title_3 IS NULL
        ELSE FALSE
    END
    COMMENT = 'Reporters only see national-level rows. Analysts see all regions.';

-- Apply to employment table
ALTER TABLE RAW.RAW_HLFS_EMPLOYMENT
    ADD ROW ACCESS POLICY RAW.REGIONAL_ACCESS_POLICY ON (SERIES_TITLE_3);

-- ════════════════════════════════════════════════════════════════════════════
-- 3. TIME TRAVEL EXAMPLES
-- Snowflake retains history for 90 days (7 on free trial).
-- Useful for debugging bad loads, or auditing data changes.
-- ════════════════════════════════════════════════════════════════════════════

USE ROLE ENGINEER_ROLE;
USE SCHEMA NZ_LABOUR_DB.RAW;

-- Query as of 1 hour ago
SELECT COUNT(*) AS rows_1hr_ago
FROM RAW_HLFS_EMPLOYMENT
    AT (OFFSET => -3600);

-- Query as of a specific timestamp (useful after a bad load)
-- SELECT * FROM RAW_HLFS_EMPLOYMENT
--     AT (TIMESTAMP => '2025-12-01 09:00:00'::TIMESTAMP_NTZ)
--     WHERE period = '2025Q3'
-- LIMIT 10;

-- UNDROP a table accidentally dropped (90-day window)
-- DROP TABLE RAW_HLFS_EMPLOYMENT;   -- simulate accident
-- UNDROP TABLE RAW_HLFS_EMPLOYMENT; -- restore in seconds

-- ════════════════════════════════════════════════════════════════════════════
-- 4. ZERO-COPY CLONING
-- Creates a dev copy instantly with no data duplication costs.
-- ════════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;

-- Clone entire database for dev work
CREATE DATABASE IF NOT EXISTS NZ_LABOUR_DB_DEV
    CLONE NZ_LABOUR_DB
    COMMENT = 'Zero-copy dev environment. Costs nothing until data diverges.';

-- Grant engineer access to dev database
GRANT USAGE ON DATABASE NZ_LABOUR_DB_DEV TO ROLE ENGINEER_ROLE;
GRANT USAGE, CREATE TABLE, CREATE VIEW ON ALL SCHEMAS IN DATABASE NZ_LABOUR_DB_DEV TO ROLE ENGINEER_ROLE;

-- ════════════════════════════════════════════════════════════════════════════
-- 5. QUERY TAGS and QUERY HISTORY (great for interview demo)
-- Show how to audit which queries ran, how long they took, and who ran them
-- ════════════════════════════════════════════════════════════════════════════

-- View query history for this project
SELECT
    query_id,
    query_text,
    role_name,
    user_name,
    warehouse_name,
    execution_status,
    ROUND(total_elapsed_time / 1000, 2) AS elapsed_seconds,
    ROUND(bytes_scanned / 1024 / 1024, 1) AS mb_scanned,
    start_time
FROM TABLE(NZ_LABOUR_DB.INFORMATION_SCHEMA.QUERY_HISTORY(
    DATE_RANGE_START => DATEADD('day', -7, CURRENT_TIMESTAMP()),
    RESULT_LIMIT => 100
))
WHERE query_tag ILIKE '%NZ_LABOUR%'
ORDER BY start_time DESC;

-- ════════════════════════════════════════════════════════════════════════════
-- 6. RESOURCE MONITORS — prevent runaway costs
-- Critical for real projects — alerts you when credit usage hits a threshold
-- ════════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE RESOURCE MONITOR NZ_LABOUR_MONITOR
    WITH CREDIT_QUOTA = 5            -- alert if more than 5 credits/month used
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 75 PERCENT DO NOTIFY       -- email alert at 75%
        ON 100 PERCENT DO SUSPEND;    -- suspend warehouse at 100%

ALTER WAREHOUSE NZ_LABOUR_WH
    SET RESOURCE_MONITOR = NZ_LABOUR_MONITOR;
