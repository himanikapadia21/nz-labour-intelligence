{{
    config(
        materialized='table',
        schema='INTERMEDIATE',
        tags=['intermediate']
    )
}}

/*
int_regional_employment.sql
────────────────────────────
Intermediate model combining HLFS quarterly employment metrics
with monthly Employment Indicators data for regional analysis.

Joins:
  stg_hlfs_employment   → quarterly rates by region/sex/age
  stg_employment_indicators → monthly filled jobs counts

Output: one row per region + year_quarter with all key employment KPIs.
Used by: mart_regional_dashboard
*/

WITH hlfs_quarterly AS (
    SELECT
        period_start_date,
        year_num,
        quarter_num,
        region,
        sex,
        age_group,
        measure_name,
        data_value,
        data_value_actual,
        units,
        is_seasonally_adjusted

    FROM {{ ref('stg_hlfs_employment') }}
    WHERE
        -- Focus on total population (all ages, both sexes) for regional view
        -- Analysts can join to age/sex breakdowns if needed
        sex IN ('Total Both Sexes', 'Total', NULL)
        AND is_seasonally_adjusted = FALSE   -- Unadjusted for regional breakdowns
),

-- Pivot key metrics into columns for easier consumption in Power BI
regional_rates AS (
    SELECT
        period_start_date,
        year_num,
        quarter_num,
        region,

        -- Employment rate
        MAX(CASE WHEN measure_name ILIKE '%employment rate%' THEN data_value END)
            AS employment_rate_pct,

        -- Unemployment rate
        MAX(CASE WHEN measure_name ILIKE '%unemployment rate%'
                  AND measure_name NOT ILIKE '%under%' THEN data_value END)
            AS unemployment_rate_pct,

        -- Labour force participation rate
        MAX(CASE WHEN measure_name ILIKE '%participation rate%' THEN data_value END)
            AS participation_rate_pct,

        -- Underutilisation rate
        MAX(CASE WHEN measure_name ILIKE '%underutilisation rate%' THEN data_value END)
            AS underutilisation_rate_pct,

        -- Employed count (in thousands from magnitude)
        MAX(CASE WHEN measure_name ILIKE '%employed%'
                  AND measure_name NOT ILIKE '%unemployed%'
                  AND units ILIKE '%number%' THEN data_value_actual END)
            AS employed_count,

        -- Unemployed count
        MAX(CASE WHEN measure_name ILIKE '%unemployed%'
                  AND units ILIKE '%number%' THEN data_value_actual END)
            AS unemployed_count

    FROM hlfs_quarterly
    GROUP BY 1, 2, 3, 4
),

-- Monthly filled jobs from Employment Indicators — more current signal
monthly_jobs AS (
    SELECT
        year_num,
        quarter_num,
        region,
        AVG(CASE WHEN measure_clean = 'Filled Jobs' THEN data_value_actual END)
            AS avg_monthly_filled_jobs,
        SUM(CASE WHEN measure_clean = 'Gross Earnings' THEN data_value_actual END)
            AS total_quarterly_gross_earnings_nzd

    FROM {{ ref('stg_employment_indicators') }}
    WHERE is_seasonally_adjusted = FALSE
    GROUP BY 1, 2, 3
),

-- Canonical list of NZ regions for completeness
nz_regions AS (
    SELECT COLUMN1 AS region FROM (
        VALUES
            ('Auckland Region'),
            ('Wellington Region'),
            ('Canterbury Region'),
            ('Waikato Region'),
            ('Bay of Plenty Region'),
            ('Otago Region'),
            ('Hawke''s Bay Region'),
            ('Manawatū-Whanganui Region'),
            ('Northland Region'),
            ('Taranaki Region'),
            ('Gisborne Region'),
            ('Tasman Region'),
            ('Nelson Region'),
            ('Marlborough Region'),
            ('West Coast Region'),
            ('Southland Region')
    ) regions
),

-- Final join
final AS (
    SELECT
        r.period_start_date,
        r.year_num,
        r.quarter_num,
        r.year_num || 'Q' || r.quarter_num::VARCHAR AS year_quarter_label,
        r.region,

        -- Employment metrics
        r.employment_rate_pct,
        r.unemployment_rate_pct,
        r.participation_rate_pct,
        r.underutilisation_rate_pct,
        r.employed_count,
        r.unemployed_count,

        -- Monthly employment indicators (aggregated to quarter)
        m.avg_monthly_filled_jobs,
        m.total_quarterly_gross_earnings_nzd,

        -- Derived
        CASE
            WHEN r.region ILIKE '%Auckland%' THEN 'North Island - Major'
            WHEN r.region ILIKE '%Wellington%' THEN 'North Island - Major'
            WHEN r.region ILIKE '%Canterbury%' THEN 'South Island - Major'
            WHEN r.region IN ('Waikato Region', 'Bay of Plenty Region') THEN 'North Island - Regional'
            WHEN r.region = 'New Zealand' THEN 'National'
            ELSE 'Other'
        END AS region_tier,

        -- Data quality flags
        CASE WHEN r.employment_rate_pct IS NULL THEN 1 ELSE 0 END AS missing_employment_rate,
        CASE WHEN r.unemployment_rate_pct IS NULL THEN 1 ELSE 0 END AS missing_unemployment_rate

    FROM regional_rates r
    LEFT JOIN monthly_jobs m
        ON r.year_num = m.year_num
        AND r.quarter_num = m.quarter_num
        AND r.region = m.region
    WHERE r.region IS NOT NULL
)

SELECT * FROM final
ORDER BY period_start_date DESC, region
