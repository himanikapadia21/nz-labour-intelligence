-- ═══════════════════════════════════════════════════════════════════════════
-- 02_create_staging_tables.sql
-- Creates the RAW schema tables that Python loads into.
-- Run after 01_setup_roles_and_databases.sql
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ENGINEER_ROLE;
USE WAREHOUSE NZ_LABOUR_WH;
USE DATABASE NZ_LABOUR_DB;
USE SCHEMA RAW;

-- ── RAW_HLFS_EMPLOYMENT ───────────────────────────────────────────────────────
-- Source: Household Labour Force Survey
-- Content: Employment rate, unemployment rate, participation rate
--          by region, age group, sex — quarterly
CREATE TABLE IF NOT EXISTS RAW_HLFS_EMPLOYMENT (
    series_reference    VARCHAR(60)     COMMENT 'Stats NZ time-series code e.g. HLFQ.S1B1AS',
    period              VARCHAR(20)     COMMENT 'Period e.g. 2025Q4',
    data_value          FLOAT           COMMENT 'The actual data value (rate, count, etc.)',
    suppressed          VARCHAR(10)     COMMENT 'S = suppressed for confidentiality',
    status              VARCHAR(30)     COMMENT 'F=Final, R=Revised, P=Provisional',
    units               VARCHAR(40)     COMMENT 'Percent, Number, Dollars, etc.',
    magnitude           INTEGER         COMMENT 'Scaling factor e.g. 1000 means values in thousands',
    subject             VARCHAR(100)    COMMENT 'High-level subject category',
    group_name          VARCHAR(100)    COMMENT 'Survey group e.g. Household Labour Force Survey',
    series_title_1      VARCHAR(200)    COMMENT 'Primary dimension e.g. Employed',
    series_title_2      VARCHAR(200)    COMMENT 'Secondary dimension e.g. Male',
    series_title_3      VARCHAR(200)    COMMENT 'Tertiary dimension e.g. Auckland Region',
    series_title_4      VARCHAR(200),
    series_title_5      VARCHAR(200),
    _ingested_at        TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    _source_file        VARCHAR(200)
)
CLUSTER BY (period)
COMMENT = 'Raw HLFS employment data from Stats NZ. Do not modify.';

-- ── RAW_QES_WAGES ─────────────────────────────────────────────────────────────
-- Source: Quarterly Employment Survey
-- Content: Average hourly earnings, weekly earnings by industry and sector
CREATE TABLE IF NOT EXISTS RAW_QES_WAGES (
    series_reference    VARCHAR(60),
    period              VARCHAR(20),
    data_value          FLOAT           COMMENT 'Wage value in NZD',
    suppressed          VARCHAR(10),
    status              VARCHAR(30),
    units               VARCHAR(40),
    magnitude           INTEGER,
    subject             VARCHAR(100),
    group_name          VARCHAR(100),
    series_title_1      VARCHAR(200)    COMMENT 'Wage measure e.g. Average Ordinary Time Hourly Earnings',
    series_title_2      VARCHAR(200)    COMMENT 'Sector e.g. Private, Public, All',
    series_title_3      VARCHAR(200)    COMMENT 'Industry e.g. Health Care, Retail Trade',
    series_title_4      VARCHAR(200),
    series_title_5      VARCHAR(200),
    _ingested_at        TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    _source_file        VARCHAR(200)
)
CLUSTER BY (period)
COMMENT = 'Raw QES wages data from Stats NZ. Do not modify.';

-- ── RAW_EMPLOYMENT_INDICATORS ─────────────────────────────────────────────────
-- Source: Employment Indicators (monthly — more frequent than HLFS)
-- Content: Filled jobs, gross earnings by industry and region
CREATE TABLE IF NOT EXISTS RAW_EMPLOYMENT_INDICATORS (
    series_reference    VARCHAR(60),
    period              VARCHAR(20)     COMMENT 'Period e.g. 2025M12 (December 2025)',
    data_value          FLOAT,
    suppressed          VARCHAR(10),
    status              VARCHAR(30),
    units               VARCHAR(40),
    magnitude           INTEGER,
    subject             VARCHAR(100),
    group_name          VARCHAR(100),
    series_title_1      VARCHAR(200)    COMMENT 'Measure e.g. Filled Jobs, Gross Earnings',
    series_title_2      VARCHAR(200)    COMMENT 'Industry ANZSIC division',
    series_title_3      VARCHAR(200)    COMMENT 'Region e.g. Auckland, Waikato',
    series_title_4      VARCHAR(200),
    series_title_5      VARCHAR(200),
    _ingested_at        TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    _source_file        VARCHAR(200)
)
CLUSTER BY (period)
COMMENT = 'Raw monthly employment indicators from Stats NZ. Do not modify.';

-- ── Audit log table ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS _INGESTION_LOG (
    log_id          INTEGER AUTOINCREMENT PRIMARY KEY,
    table_name      VARCHAR(100),
    run_timestamp   TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP(),
    rows_loaded     INTEGER,
    source_files    VARCHAR(500),
    status          VARCHAR(20),
    error_message   VARCHAR(2000),
    duration_secs   FLOAT
)
COMMENT = 'Audit trail for all pipeline ingestion runs.';

-- ── Verify ────────────────────────────────────────────────────────────────────
SHOW TABLES IN SCHEMA NZ_LABOUR_DB.RAW;
