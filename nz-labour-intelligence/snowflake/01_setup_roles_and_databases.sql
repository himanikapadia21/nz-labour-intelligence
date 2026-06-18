-- ═══════════════════════════════════════════════════════════════════════════
-- 01_setup_roles_and_databases.sql
-- Run as ACCOUNTADMIN on a fresh Snowflake trial account.
-- Sets up the complete role hierarchy, virtual warehouse, and databases.
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;

-- ── 1. Virtual Warehouse ──────────────────────────────────────────────────────
-- X-SMALL is plenty for this project — scales to zero when idle (free trial safe)
CREATE WAREHOUSE IF NOT EXISTS NZ_LABOUR_WH
    WAREHOUSE_SIZE    = 'X-SMALL'
    AUTO_SUSPEND      = 60          -- suspend after 60s idle
    AUTO_RESUME       = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'NZ Labour Intelligence Platform — compute warehouse';

-- ── 2. Databases ─────────────────────────────────────────────────────────────
CREATE DATABASE IF NOT EXISTS NZ_LABOUR_DB
    COMMENT = 'NZ Labour Market Intelligence — production';

-- Dev clone (zero-copy — created after first data load, see run_pipeline.py)
-- CREATE DATABASE NZ_LABOUR_DB_DEV CLONE NZ_LABOUR_DB;

-- ── 3. Schemas ────────────────────────────────────────────────────────────────
-- RAW      → direct from source, untransformed
-- STAGING  → dbt staging models (stg_*)
-- INTERMEDIATE → dbt intermediate models (int_*)
-- MART     → dbt mart models (mart_*) — Power BI connects here
-- AUDIT    → pipeline logs and data quality results

CREATE SCHEMA IF NOT EXISTS NZ_LABOUR_DB.RAW          COMMENT = 'Raw ingested data from Stats NZ';
CREATE SCHEMA IF NOT EXISTS NZ_LABOUR_DB.STAGING       COMMENT = 'dbt staging layer — cleaned source data';
CREATE SCHEMA IF NOT EXISTS NZ_LABOUR_DB.INTERMEDIATE  COMMENT = 'dbt intermediate layer — business logic';
CREATE SCHEMA IF NOT EXISTS NZ_LABOUR_DB.MART          COMMENT = 'dbt mart layer — final models for reporting';
CREATE SCHEMA IF NOT EXISTS NZ_LABOUR_DB.AUDIT         COMMENT = 'Pipeline audit logs and test results';

-- ── 4. Role Hierarchy ─────────────────────────────────────────────────────────
--
--  ACCOUNTADMIN
--       │
--  SYSADMIN
--       │
--  ENGINEER_ROLE  ← full read/write on all schemas
--       │
--  ANALYST_ROLE   ← read on STAGING, INTERMEDIATE, MART
--       │
--  REPORTER_ROLE  ← read on MART only (subject to row/column masking)

CREATE ROLE IF NOT EXISTS ENGINEER_ROLE  COMMENT = 'Data engineers — full pipeline access';
CREATE ROLE IF NOT EXISTS ANALYST_ROLE   COMMENT = 'Data analysts — read transformed data';
CREATE ROLE IF NOT EXISTS REPORTER_ROLE  COMMENT = 'Power BI / report consumers — mart only';

-- Role hierarchy — each role inherits from the one above
GRANT ROLE ENGINEER_ROLE TO ROLE SYSADMIN;
GRANT ROLE ANALYST_ROLE  TO ROLE ENGINEER_ROLE;
GRANT ROLE REPORTER_ROLE TO ROLE ANALYST_ROLE;

-- ── 5. Warehouse grants ───────────────────────────────────────────────────────
GRANT USAGE ON WAREHOUSE NZ_LABOUR_WH TO ROLE ENGINEER_ROLE;
GRANT USAGE ON WAREHOUSE NZ_LABOUR_WH TO ROLE ANALYST_ROLE;
GRANT USAGE ON WAREHOUSE NZ_LABOUR_WH TO ROLE REPORTER_ROLE;

-- ── 6. Database and schema grants ─────────────────────────────────────────────
GRANT USAGE ON DATABASE NZ_LABOUR_DB TO ROLE ENGINEER_ROLE;
GRANT USAGE ON DATABASE NZ_LABOUR_DB TO ROLE ANALYST_ROLE;
GRANT USAGE ON DATABASE NZ_LABOUR_DB TO ROLE REPORTER_ROLE;

-- Engineer — full access to all schemas
GRANT USAGE, CREATE TABLE, CREATE VIEW, CREATE STAGE, CREATE PIPE
    ON SCHEMA NZ_LABOUR_DB.RAW         TO ROLE ENGINEER_ROLE;
GRANT USAGE, CREATE TABLE, CREATE VIEW
    ON SCHEMA NZ_LABOUR_DB.STAGING     TO ROLE ENGINEER_ROLE;
GRANT USAGE, CREATE TABLE, CREATE VIEW
    ON SCHEMA NZ_LABOUR_DB.INTERMEDIATE TO ROLE ENGINEER_ROLE;
GRANT USAGE, CREATE TABLE, CREATE VIEW
    ON SCHEMA NZ_LABOUR_DB.MART        TO ROLE ENGINEER_ROLE;
GRANT USAGE, CREATE TABLE
    ON SCHEMA NZ_LABOUR_DB.AUDIT       TO ROLE ENGINEER_ROLE;

-- Analyst — read on transformed schemas only
GRANT USAGE ON SCHEMA NZ_LABOUR_DB.STAGING      TO ROLE ANALYST_ROLE;
GRANT USAGE ON SCHEMA NZ_LABOUR_DB.INTERMEDIATE TO ROLE ANALYST_ROLE;
GRANT USAGE ON SCHEMA NZ_LABOUR_DB.MART         TO ROLE ANALYST_ROLE;

-- Reporter — mart only
GRANT USAGE ON SCHEMA NZ_LABOUR_DB.MART TO ROLE REPORTER_ROLE;

-- Future grants — automatically apply to new tables created in each schema
GRANT SELECT ON FUTURE TABLES IN SCHEMA NZ_LABOUR_DB.STAGING      TO ROLE ANALYST_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA NZ_LABOUR_DB.INTERMEDIATE  TO ROLE ANALYST_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA NZ_LABOUR_DB.MART          TO ROLE ANALYST_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA NZ_LABOUR_DB.MART          TO ROLE REPORTER_ROLE;
GRANT SELECT ON FUTURE VIEWS  IN SCHEMA NZ_LABOUR_DB.MART          TO ROLE REPORTER_ROLE;

-- ── 7. Service users ─────────────────────────────────────────────────────────
-- Create a dedicated service user for the Python pipeline (not your personal login)
-- Replace 'STRONG_PASSWORD_HERE' before running

CREATE USER IF NOT EXISTS NZ_LABOUR_PIPELINE_USER
    PASSWORD            = 'STRONG_PASSWORD_HERE'
    DEFAULT_ROLE        = ENGINEER_ROLE
    DEFAULT_WAREHOUSE   = NZ_LABOUR_WH
    DEFAULT_NAMESPACE   = NZ_LABOUR_DB.RAW
    MUST_CHANGE_PASSWORD = FALSE
    COMMENT             = 'Service account for ingestion pipeline';

GRANT ROLE ENGINEER_ROLE TO USER NZ_LABOUR_PIPELINE_USER;

-- ── 8. Verify setup ───────────────────────────────────────────────────────────
SHOW SCHEMAS IN DATABASE NZ_LABOUR_DB;
SHOW ROLES LIKE '%LABOUR%';
SHOW USERS LIKE '%PIPELINE%';
