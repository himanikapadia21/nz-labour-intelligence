-- ═══════════════════════════════════════════════════════════════════════════════
-- snowflake_time_travel_demo.sql
-- ───────────────────────────────
-- Portfolio-ready demonstration of Snowflake Time Travel.
-- Save as a Named Query in Snowflake — great talking point in interviews.
--
-- Run in dbt:  dbt compile --select snowflake_time_travel_demo
-- Run directly in Snowflake worksheet after pasting the compiled SQL.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── Scenario 1: How many rows did we have before today's pipeline run? ─────────
-- Useful for validating that the pipeline loaded data (row count should increase).

SELECT
    'Current'            AS snapshot,
    COUNT(*)             AS row_count,
    MAX(_ingested_at)    AS last_ingested,
    MIN(period)          AS earliest_period,
    MAX(period)          AS latest_period
FROM {{ source('raw', 'RAW_HLFS_EMPLOYMENT') }}

UNION ALL

SELECT
    '1 hour ago'         AS snapshot,
    COUNT(*)             AS row_count,
    MAX(_ingested_at)    AS last_ingested,
    MIN(period)          AS earliest_period,
    MAX(period)          AS latest_period
FROM {{ source('raw', 'RAW_HLFS_EMPLOYMENT') }}
    AT (OFFSET => -3600)   -- 3600 seconds = 1 hour

UNION ALL

SELECT
    '24 hours ago'       AS snapshot,
    COUNT(*)             AS row_count,
    MAX(_ingested_at)    AS last_ingested,
    MIN(period)          AS earliest_period,
    MAX(period)          AS latest_period
FROM {{ source('raw', 'RAW_HLFS_EMPLOYMENT') }}
    AT (OFFSET => -86400)  -- 86400 seconds = 24 hours

ORDER BY snapshot;


-- ── Scenario 2: Compare current wages with values from last week ───────────────
-- Demonstrates auditing: "did our pipeline change the wage figures?"
-- Useful if a source file is revised by Stats NZ between releases.

/*
SELECT
    curr.series_reference,
    curr.period,
    curr.data_value                                          AS wage_current,
    prev.data_value                                          AS wage_last_week,
    ROUND(curr.data_value - prev.data_value, 4)             AS wage_change,
    CASE
        WHEN prev.data_value IS NULL     THEN 'NEW ROW'
        WHEN curr.data_value IS NULL     THEN 'ROW DELETED'
        WHEN curr.data_value != prev.data_value THEN 'VALUE CHANGED'
        ELSE 'UNCHANGED'
    END                                                      AS change_type

FROM {{ source('raw', 'RAW_QES_WAGES') }} curr
FULL OUTER JOIN {{ source('raw', 'RAW_QES_WAGES') }}
    AT (OFFSET => -604800) prev   -- 604800 seconds = 7 days
    ON curr.series_reference = prev.series_reference
   AND curr.period = prev.period

WHERE curr.data_value != prev.data_value
   OR prev.data_value IS NULL
   OR curr.data_value IS NULL

ORDER BY change_type, curr.series_reference;
*/


-- ── Scenario 3: UNDROP example (comment shows how to recover a dropped table) ──
-- Never needs to run — shows awareness of Snowflake disaster recovery.

/*
-- Simulate a bad DROP:
DROP TABLE NZ_LABOUR_DB.RAW.RAW_HLFS_EMPLOYMENT;

-- Verify it's gone:
SHOW TABLES LIKE 'RAW_HLFS_EMPLOYMENT' IN SCHEMA NZ_LABOUR_DB.RAW;

-- Recover instantly — no backup restore needed:
UNDROP TABLE NZ_LABOUR_DB.RAW.RAW_HLFS_EMPLOYMENT;

-- Confirm recovery:
SELECT COUNT(*) FROM NZ_LABOUR_DB.RAW.RAW_HLFS_EMPLOYMENT;
*/
