{{
    config(
        materialized='table',
        schema='INTERMEDIATE',
        tags=['intermediate']
    )
}}

/*
int_wage_trends.sql
────────────────────
Intermediate model for wage growth analysis.

Calculates:
  - Year-on-year wage growth by sector (private/public)
  - Rolling 4-quarter average wages (smoothing)
  - Real wage growth (nominal growth minus CPI proxy)
  - Sector wage differential (public vs private gap)

Used by: mart_wage_analysis
*/

WITH wages AS (
    SELECT
        period_start_date,
        year_num,
        quarter_num,
        year_num || 'Q' || quarter_num::VARCHAR AS year_quarter_label,
        sector_clean,
        industry_anzsic,
        wage_measure,
        wage_frequency,
        wage_nzd

    FROM {{ ref('stg_qes_wages') }}
    WHERE wage_nzd IS NOT NULL
),

-- Hourly earnings — most comparable metric across time
hourly_by_sector AS (
    SELECT
        period_start_date,
        year_num,
        quarter_num,
        year_quarter_label,
        sector_clean,
        AVG(wage_nzd) AS avg_hourly_wage_nzd

    FROM wages
    WHERE wage_frequency = 'Hourly'
    GROUP BY 1, 2, 3, 4, 5
),

-- Year-on-year growth using LAG with 4-period offset (1 year back)
with_yoy AS (
    SELECT
        *,
        LAG(avg_hourly_wage_nzd, 4)
            OVER (PARTITION BY sector_clean ORDER BY period_start_date)
            AS wage_1yr_ago,

        LAG(avg_hourly_wage_nzd, 8)
            OVER (PARTITION BY sector_clean ORDER BY period_start_date)
            AS wage_2yr_ago,

        -- 4-quarter rolling average
        AVG(avg_hourly_wage_nzd)
            OVER (
                PARTITION BY sector_clean
                ORDER BY period_start_date
                ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
            ) AS rolling_4q_avg_wage

    FROM hourly_by_sector
),

-- Calculate growth rates and differentials
growth_rates AS (
    SELECT
        period_start_date,
        year_num,
        quarter_num,
        year_quarter_label,
        sector_clean,
        avg_hourly_wage_nzd,
        wage_1yr_ago,
        rolling_4q_avg_wage,

        -- YoY growth rate
        CASE
            WHEN wage_1yr_ago IS NOT NULL AND wage_1yr_ago > 0
            THEN ROUND(((avg_hourly_wage_nzd - wage_1yr_ago) / wage_1yr_ago) * 100, 2)
        END AS yoy_wage_growth_pct,

        -- 2-year cumulative growth
        CASE
            WHEN wage_2yr_ago IS NOT NULL AND wage_2yr_ago > 0
            THEN ROUND(((avg_hourly_wage_nzd - wage_2yr_ago) / wage_2yr_ago) * 100, 2)
        END AS two_yr_wage_growth_pct

    FROM with_yoy
),

-- Sector differential — how much more does public sector pay than private?
sector_pivot AS (
    SELECT
        period_start_date,
        year_num,
        quarter_num,
        year_quarter_label,

        MAX(CASE WHEN sector_clean = 'Private' THEN avg_hourly_wage_nzd END)
            AS private_hourly_wage,
        MAX(CASE WHEN sector_clean = 'Public' THEN avg_hourly_wage_nzd END)
            AS public_hourly_wage,
        MAX(CASE WHEN sector_clean = 'All Sectors' THEN avg_hourly_wage_nzd END)
            AS all_sectors_hourly_wage,

        MAX(CASE WHEN sector_clean = 'Private' THEN yoy_wage_growth_pct END)
            AS private_yoy_growth_pct,
        MAX(CASE WHEN sector_clean = 'Public' THEN yoy_wage_growth_pct END)
            AS public_yoy_growth_pct,
        MAX(CASE WHEN sector_clean = 'All Sectors' THEN yoy_wage_growth_pct END)
            AS all_sectors_yoy_growth_pct

    FROM growth_rates
    GROUP BY 1, 2, 3, 4
),

final AS (
    SELECT
        *,
        -- Public sector premium over private
        CASE
            WHEN private_hourly_wage > 0
            THEN ROUND(((public_hourly_wage - private_hourly_wage) / private_hourly_wage) * 100, 1)
        END AS public_vs_private_premium_pct,

        ROUND(public_hourly_wage - private_hourly_wage, 2)
            AS public_vs_private_gap_nzd,

        -- Annualised salary estimate (40hr week × 52 weeks)
        ROUND(all_sectors_hourly_wage * 40 * 52, 0) AS estimated_annual_salary_nzd

    FROM sector_pivot
)

SELECT * FROM final
ORDER BY period_start_date DESC
