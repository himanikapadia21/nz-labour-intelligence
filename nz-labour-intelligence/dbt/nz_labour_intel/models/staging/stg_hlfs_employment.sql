{{
    config(
        materialized='view',
        schema='STAGING',
        tags=['staging', 'hlfs']
    )
}}

/*
stg_hlfs_employment.sql
────────────────────────
Staging model for the Household Labour Force Survey (HLFS).

Responsibilities:
  - Rename columns to human-readable names
  - Parse the Stats NZ period format ('2025Q4') into proper date fields
  - Filter out suppressed rows and bad data
  - Decode Stats NZ series codes into readable dimension labels
  - Add derived fields (year, quarter, is_seasonally_adjusted)

Source: RAW.RAW_HLFS_EMPLOYMENT
Stats NZ series format: HLFQ.SXXX (Q = quarterly, S = seasonally adjusted)
*/

WITH source AS (
    SELECT * FROM {{ source('raw', 'RAW_HLFS_EMPLOYMENT') }}
),

-- Parse the period string into year and quarter integers
parsed_period AS (
    SELECT
        *,
        -- Stats NZ uses '2025Q4' format
        TRY_CAST(LEFT(period, 4) AS INTEGER)                    AS year_num,
        TRY_CAST(RIGHT(period, 1) AS INTEGER)                   AS quarter_num,
        -- Convert to a proper date (first day of the quarter)
        CASE RIGHT(period, 1)
            WHEN '1' THEN DATEADD('month',  0, DATE_TRUNC('year', TO_DATE(LEFT(period, 4) || '-01-01')))
            WHEN '2' THEN DATEADD('month',  3, DATE_TRUNC('year', TO_DATE(LEFT(period, 4) || '-01-01')))
            WHEN '3' THEN DATEADD('month',  6, DATE_TRUNC('year', TO_DATE(LEFT(period, 4) || '-01-01')))
            WHEN '4' THEN DATEADD('month',  9, DATE_TRUNC('year', TO_DATE(LEFT(period, 4) || '-01-01')))
        END                                                      AS period_start_date
    FROM source
    WHERE period LIKE '____Q_'        -- Only quarterly periods
),

cleaned AS (
    SELECT
        -- Keys
        series_reference,
        period,
        period_start_date,
        year_num,
        quarter_num,

        -- Measure
        data_value,
        units,
        COALESCE(NULLIF(suppressed, ''), 'N') AS is_suppressed,
        status,
        CAST(magnitude AS INTEGER) AS magnitude,

        -- Dimensions decoded from series titles
        -- Stats NZ packs dimensions into 5 freeform title columns
        series_title_1 AS measure_name,            -- e.g. 'Employed', 'Unemployed', 'Unemployment Rate'
        series_title_2 AS sex,                     -- e.g. 'Male', 'Female', 'Total Both Sexes'
        series_title_3 AS region,                  -- e.g. 'Auckland Region', 'New Zealand'
        series_title_4 AS age_group,               -- e.g. '15-24 years', 'All ages'
        series_title_5 AS adjustment_type,         -- e.g. 'Seasonally Adjusted', 'Unadjusted'

        -- Derived flags
        CASE
            WHEN series_title_5 ILIKE '%seasonal%' THEN TRUE
            WHEN series_title_1 ILIKE '%seasonally%' THEN TRUE
            ELSE FALSE
        END AS is_seasonally_adjusted,

        CASE
            WHEN units ILIKE 'percent' THEN TRUE
            ELSE FALSE
        END AS is_rate_metric,

        -- The actual value scaled by magnitude
        -- Magnitude 1000 means values are in thousands → multiply to get actuals
        CASE
            WHEN CAST(magnitude AS INTEGER) > 1 THEN data_value * CAST(magnitude AS INTEGER)
            ELSE data_value
        END AS data_value_actual,

        -- Metadata
        _ingested_at,
        _source_file

    FROM parsed_period
    WHERE
        -- Remove rows with no data value and no suppression flag
        (data_value IS NOT NULL OR suppressed = 'S')
        -- Filter to meaningful time range
        AND year_num >= {{ var('start_year') }}
)

SELECT * FROM cleaned
