{{
    config(
        materialized='table',
        schema='MART',
        tags=['mart', 'power_bi']
    )
}}

/*
mart_regional_dashboard.sql
────────────────────────────
Final mart model — the primary table Power BI connects to for the
regional employment dashboard.

Design choices:
  - Wide table (denormalised) — Power BI performs better with fewer joins
  - All dimension columns included — slicers work without lookups
  - Rounded values — cleaner in report visuals
  - Standardised NULL handling — Power BI handles NULLs gracefully

Grain: one row per region + quarter
*/

WITH regional AS (
    SELECT * FROM {{ ref('int_regional_employment') }}
),

-- National NZ totals for comparison line in visuals
nz_national AS (
    SELECT
        period_start_date,
        year_num,
        quarter_num,
        employment_rate_pct          AS nz_employment_rate_pct,
        unemployment_rate_pct        AS nz_unemployment_rate_pct,
        participation_rate_pct       AS nz_participation_rate_pct,
        underutilisation_rate_pct    AS nz_underutilisation_rate_pct

    FROM {{ ref('int_regional_employment') }}
    WHERE region IN ('New Zealand', 'Total New Zealand')
),

final AS (
    SELECT
        -- ── Dimensions (for Power BI slicers) ─────────────────────────────
        r.period_start_date,
        r.year_num,
        r.quarter_num,
        r.year_quarter_label,
        r.region,
        r.region_tier,

        -- ── Key metrics ───────────────────────────────────────────────────
        ROUND(r.employment_rate_pct, 1)          AS employment_rate_pct,
        ROUND(r.unemployment_rate_pct, 1)        AS unemployment_rate_pct,
        ROUND(r.participation_rate_pct, 1)       AS participation_rate_pct,
        ROUND(r.underutilisation_rate_pct, 1)    AS underutilisation_rate_pct,

        -- People counts (rounded to nearest 100 — Stats NZ rounding convention)
        ROUND(r.employed_count / 100.0, 0) * 100 AS employed_count,
        ROUND(r.unemployed_count / 100.0, 0) * 100 AS unemployed_count,

        -- Monthly indicators (quarter aggregates)
        ROUND(r.avg_monthly_filled_jobs, 0)      AS avg_monthly_filled_jobs,
        ROUND(r.total_quarterly_gross_earnings_nzd / 1000000000.0, 2)
                                                  AS gross_earnings_billions_nzd,

        -- ── National benchmarks (for comparison) ──────────────────────────
        ROUND(nz.nz_employment_rate_pct, 1)        AS nz_employment_rate_pct,
        ROUND(nz.nz_unemployment_rate_pct, 1)      AS nz_unemployment_rate_pct,
        ROUND(nz.nz_participation_rate_pct, 1)     AS nz_participation_rate_pct,
        ROUND(nz.nz_underutilisation_rate_pct, 1)  AS nz_underutilisation_rate_pct,

        -- ── Derived: region vs national gap ───────────────────────────────
        ROUND(r.unemployment_rate_pct - nz.nz_unemployment_rate_pct, 1)
            AS unemployment_rate_vs_nz_pp,          -- pp = percentage points

        ROUND(r.employment_rate_pct - nz.nz_employment_rate_pct, 1)
            AS employment_rate_vs_nz_pp,

        -- ── Data quality ──────────────────────────────────────────────────
        r.missing_employment_rate,
        r.missing_unemployment_rate,

        -- Timestamp for Power BI refresh tracking
        CURRENT_TIMESTAMP()                      AS mart_refreshed_at

    FROM regional r
    LEFT JOIN nz_national nz
        ON r.period_start_date = nz.period_start_date

    -- Exclude the national total row itself (it's used for benchmarks above)
    WHERE r.region NOT IN ('New Zealand', 'Total New Zealand')
)

SELECT * FROM final
ORDER BY period_start_date DESC, region
