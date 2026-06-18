{{
    config(
        materialized='view',
        schema='STAGING',
        tags=['staging', 'employment_indicators']
    )
}}

/*
stg_employment_indicators.sql
──────────────────────────────
Staging model for Stats NZ monthly Employment Indicators.

Updated monthly (more current than quarterly HLFS).
Key metrics:
  - Filled jobs by industry and region
  - Gross earnings by industry and region

Period format: '2025M12' = December 2025
*/

WITH source AS (
    SELECT * FROM {{ source('raw', 'RAW_EMPLOYMENT_INDICATORS') }}
),

parsed AS (
    SELECT
        *,
        -- Monthly periods: '2025M12' format
        TRY_CAST(LEFT(period, 4) AS INTEGER)         AS year_num,
        TRY_CAST(SUBSTRING(period, 6, 2) AS INTEGER) AS month_num,
        -- Build a proper date (1st of the month)
        TRY_TO_DATE(
            LEFT(period, 4) || '-' ||
            LPAD(SUBSTRING(period, 6, 2), 2, '0') || '-01',
            'YYYY-MM-DD'
        ) AS period_start_date
    FROM source
    WHERE period LIKE '____M__'    -- Monthly format
       OR period LIKE '____M_'     -- Single-digit month
),

cleaned AS (
    SELECT
        series_reference,
        period,
        period_start_date,
        year_num,
        month_num,

        -- Quarter derived from month (useful for joining to quarterly models)
        CEIL(month_num / 3.0)::INTEGER AS quarter_num,

        data_value,
        units,
        status,
        magnitude,

        -- Measure type
        series_title_1 AS measure_name,
        CASE
            WHEN series_title_1 ILIKE '%filled job%'   THEN 'Filled Jobs'
            WHEN series_title_1 ILIKE '%gross earning%' THEN 'Gross Earnings'
            ELSE series_title_1
        END AS measure_clean,

        -- Industry (ANZSIC division)
        series_title_2 AS industry,

        -- Region
        series_title_3 AS region,

        -- Adjustment
        series_title_4 AS adjustment_type,
        CASE
            WHEN series_title_4 ILIKE '%seasonal%' THEN TRUE
            ELSE FALSE
        END AS is_seasonally_adjusted,

        -- Scale values by magnitude
        CASE
            WHEN magnitude > 1 THEN data_value * magnitude
            ELSE data_value
        END AS data_value_actual,

        _ingested_at,
        _source_file

    FROM parsed
    WHERE
        data_value IS NOT NULL
        AND year_num >= {{ var('start_year') }}
)

SELECT * FROM cleaned
