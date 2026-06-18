{{
    config(
        materialized='view',
        schema='STAGING',
        tags=['staging', 'qes']
    )
}}

/*
stg_qes_wages.sql
──────────────────
Staging model for the Quarterly Employment Survey (QES) wages data.

QES measures average earnings — used by employers, unions, and government
to track wage growth, sector differentials, and the gender pay gap.

Key metrics in this dataset:
  - Average Ordinary Time Hourly Earnings (AOTHE)
  - Average Weekly Earnings including overtime
  - Full-time equivalent (FTE) weekly earnings
  - Public vs private sector breakdown
*/

WITH source AS (
    SELECT * FROM {{ source('raw', 'RAW_QES_WAGES') }}
),

parsed AS (
    SELECT
        *,
        TRY_CAST(LEFT(period, 4) AS INTEGER) AS year_num,
        TRY_CAST(RIGHT(period, 1) AS INTEGER) AS quarter_num,
        CASE RIGHT(period, 1)
            WHEN '1' THEN DATEADD('month',  0, TO_DATE(LEFT(period, 4) || '-01-01'))
            WHEN '2' THEN DATEADD('month',  3, TO_DATE(LEFT(period, 4) || '-01-01'))
            WHEN '3' THEN DATEADD('month',  6, TO_DATE(LEFT(period, 4) || '-01-01'))
            WHEN '4' THEN DATEADD('month',  9, TO_DATE(LEFT(period, 4) || '-01-01'))
        END AS period_start_date
    FROM source
    WHERE period LIKE '____Q_'
),

cleaned AS (
    SELECT
        series_reference,
        period,
        period_start_date,
        year_num,
        quarter_num,

        -- The wage value
        data_value,
        units,
        status,
        magnitude,

        -- Wage type from series_title_1
        -- e.g. 'Ordinary Time Hourly Earnings' / 'Weekly Earnings'
        series_title_1 AS wage_measure,

        -- Sector from series_title_2
        -- Values: 'Private Sector', 'Public Sector', 'All Sectors'
        series_title_2 AS sector,
        CASE
            WHEN series_title_2 ILIKE '%private%' THEN 'Private'
            WHEN series_title_2 ILIKE '%public%'  THEN 'Public'
            WHEN series_title_2 ILIKE '%all%'     THEN 'All Sectors'
            ELSE 'Other'
        END AS sector_clean,

        -- Industry from series_title_3
        series_title_3 AS industry_anzsic,

        -- Whether this is an hourly or weekly measure
        CASE
            WHEN series_title_1 ILIKE '%hourly%' THEN 'Hourly'
            WHEN series_title_1 ILIKE '%weekly%' THEN 'Weekly'
            ELSE 'Other'
        END AS wage_frequency,

        -- NZD value — magnitude is typically 1 for wages (already in dollars)
        data_value AS wage_nzd,

        _ingested_at,
        _source_file

    FROM parsed
    WHERE
        data_value IS NOT NULL
        AND data_value > 0
        AND year_num >= {{ var('start_year') }}
)

SELECT * FROM cleaned
