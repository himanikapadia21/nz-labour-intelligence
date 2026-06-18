{{
    config(
        materialized='table',
        schema='MART',
        tags=['mart', 'power_bi']
    )
}}

/*
mart_industry_wages.sql
────────────────────────
Industry-level wage breakdown for Power BI bar/rank charts.

Grain: one row per industry + quarter (hourly wages only).

Separate from mart_wage_analysis (which is sector-level) to keep
the grain clean — mixing industry and sector in one table causes
fan-out when Power BI creates relationships.
*/

WITH industry_wages AS (
    SELECT
        period_start_date,
        year_num,
        quarter_num,
        year_num || 'Q' || quarter_num::VARCHAR AS year_quarter_label,
        industry_anzsic,
        wage_frequency,
        wage_nzd

    FROM {{ ref('stg_qes_wages') }}
    WHERE
        wage_frequency = 'Hourly'
        AND wage_nzd IS NOT NULL
        AND wage_nzd > 0
        AND industry_anzsic IS NOT NULL
        AND TRIM(industry_anzsic) NOT IN ('', 'All Industries', 'Total')
),

-- Aggregate to one row per industry + quarter
aggregated AS (
    SELECT
        period_start_date,
        year_num,
        quarter_num,
        year_quarter_label,
        industry_anzsic,
        ROUND(AVG(wage_nzd), 2)  AS avg_hourly_wage_nzd,
        COUNT(*)                  AS series_count

    FROM industry_wages
    GROUP BY 1, 2, 3, 4, 5
),

-- Add rankings within each quarter
ranked AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY period_start_date ORDER BY avg_hourly_wage_nzd DESC)
            AS wage_rank_highest,

        RANK() OVER (PARTITION BY period_start_date ORDER BY avg_hourly_wage_nzd ASC)
            AS wage_rank_lowest,

        ROUND(PERCENT_RANK() OVER (PARTITION BY period_start_date ORDER BY avg_hourly_wage_nzd) * 100, 0)
            AS wage_percentile_pct,

        -- YoY wage change for this industry
        LAG(avg_hourly_wage_nzd, 4)
            OVER (PARTITION BY industry_anzsic ORDER BY period_start_date)
            AS wage_1yr_ago_nzd

    FROM aggregated
),

final AS (
    SELECT
        period_start_date,
        year_num,
        quarter_num,
        year_quarter_label,
        industry_anzsic,
        avg_hourly_wage_nzd,
        wage_rank_highest,
        wage_rank_lowest,
        wage_percentile_pct,

        -- Wage band label (for Power BI conditional formatting / legend)
        CASE
            WHEN wage_percentile_pct >= 75 THEN 'High Wage (Top 25%)'
            WHEN wage_percentile_pct >= 25 THEN 'Middle Wage'
            ELSE 'Low Wage (Bottom 25%)'
        END AS wage_band,

        -- YoY growth
        wage_1yr_ago_nzd,
        CASE
            WHEN wage_1yr_ago_nzd IS NOT NULL AND wage_1yr_ago_nzd > 0
            THEN ROUND(((avg_hourly_wage_nzd - wage_1yr_ago_nzd) / wage_1yr_ago_nzd) * 100, 2)
        END AS yoy_wage_growth_pct,

        -- Annualised salary estimate (40hr week × 52 weeks — for context cards)
        ROUND(avg_hourly_wage_nzd * 40 * 52, 0) AS estimated_annual_salary_nzd,

        CURRENT_TIMESTAMP() AS mart_refreshed_at

    FROM ranked
)

SELECT * FROM final
ORDER BY period_start_date DESC, wage_rank_highest
