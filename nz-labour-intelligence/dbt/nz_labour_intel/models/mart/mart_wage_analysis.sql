{{
    config(
        materialized='table',
        schema='MART',
        tags=['mart', 'power_bi']
    )
}}

/*
mart_wage_analysis.sql
───────────────────────
Final mart model for the wage analysis dashboard in Power BI.

Combines:
  - Quarterly wage trends (private vs public sector)
  - YoY growth rates
  - Sector premium analysis
  - Industry-level wage breakdowns

Grain: one row per quarter + sector combination
*/

WITH wage_trends AS (
    SELECT * FROM {{ ref('int_wage_trends') }}
),

-- Industry-level wages (more granular than sector)
industry_wages AS (
    SELECT
        period_start_date,
        year_num,
        quarter_num,
        industry_anzsic,
        wage_frequency,
        AVG(wage_nzd) AS avg_wage_nzd,
        COUNT(*) AS series_count

    FROM {{ ref('stg_qes_wages') }}
    WHERE
        wage_frequency = 'Hourly'
        AND industry_anzsic IS NOT NULL
        AND industry_anzsic NOT IN ('', 'All Industries', 'Total')
    GROUP BY 1, 2, 3, 4, 5
),

-- Rank industries by wage level per quarter
industry_ranked AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY period_start_date ORDER BY avg_wage_nzd DESC)
            AS wage_rank_highest,
        RANK() OVER (PARTITION BY period_start_date ORDER BY avg_wage_nzd ASC)
            AS wage_rank_lowest,
        PERCENT_RANK() OVER (PARTITION BY period_start_date ORDER BY avg_wage_nzd)
            AS wage_percentile

    FROM industry_wages
),

-- Sector summary mart (wide format for Power BI)
sector_mart AS (
    SELECT
        period_start_date,
        year_num,
        quarter_num,
        year_quarter_label,

        -- Wages
        ROUND(private_hourly_wage, 2)        AS private_hourly_wage_nzd,
        ROUND(public_hourly_wage, 2)         AS public_hourly_wage_nzd,
        ROUND(all_sectors_hourly_wage, 2)    AS all_sectors_hourly_wage_nzd,

        -- Growth
        ROUND(private_yoy_growth_pct, 2)     AS private_wage_yoy_growth_pct,
        ROUND(public_yoy_growth_pct, 2)      AS public_wage_yoy_growth_pct,
        ROUND(all_sectors_yoy_growth_pct, 2) AS all_sectors_wage_yoy_growth_pct,

        -- Sector differential
        ROUND(public_vs_private_premium_pct, 1) AS public_premium_pct,
        ROUND(public_vs_private_gap_nzd, 2)    AS public_vs_private_gap_nzd,

        -- Annual salary estimate (for "if you worked full-time" context)
        estimated_annual_salary_nzd,

        -- Derived labels for Power BI conditional formatting
        CASE
            WHEN all_sectors_yoy_growth_pct >= 5   THEN 'Strong Growth (5%+)'
            WHEN all_sectors_yoy_growth_pct >= 2.5 THEN 'Moderate Growth (2.5-5%)'
            WHEN all_sectors_yoy_growth_pct >= 0   THEN 'Slow Growth (0-2.5%)'
            WHEN all_sectors_yoy_growth_pct < 0    THEN 'Wage Decline'
            ELSE 'Unknown'
        END AS growth_category,

        CURRENT_TIMESTAMP() AS mart_refreshed_at

    FROM wage_trends
),

-- Industry mart (long format — better for bar charts in Power BI)
industry_mart AS (
    SELECT
        ir.period_start_date,
        ir.year_num,
        ir.quarter_num,
        ir.industry_anzsic,
        ROUND(ir.avg_wage_nzd, 2)    AS avg_hourly_wage_nzd,
        ir.wage_rank_highest,
        ir.wage_rank_lowest,
        ROUND(ir.wage_percentile * 100, 0) AS wage_percentile_pct,

        -- Is this a high, middle, or low wage industry?
        CASE
            WHEN ir.wage_percentile >= 0.75 THEN 'High Wage (Top 25%)'
            WHEN ir.wage_percentile >= 0.25 THEN 'Middle Wage'
            ELSE 'Low Wage (Bottom 25%)'
        END AS wage_band,

        CURRENT_TIMESTAMP() AS mart_refreshed_at

    FROM industry_ranked ir
)

-- We output sector_mart as the main grain for this model
-- Industry breakdown is exposed via mart_industry_wages (separate model for clarity)
SELECT * FROM sector_mart
ORDER BY period_start_date DESC
