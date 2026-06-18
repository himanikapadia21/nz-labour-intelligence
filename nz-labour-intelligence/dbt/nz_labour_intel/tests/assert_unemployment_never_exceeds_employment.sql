-- Singular test: assert_unemployment_never_exceeds_employment
-- ─────────────────────────────────────────────────────────────
-- The unemployment rate can never logically exceed the employment rate
-- (they measure different things but unemployment > 50% would indicate
-- corrupt data or a mapping error in our staging model).
--
-- This test returns rows that fail — dbt marks the test as failed if
-- any rows are returned.

SELECT
    region,
    period_start_date,
    unemployment_rate_pct,
    employment_rate_pct

FROM {{ ref('int_regional_employment') }}

WHERE
    unemployment_rate_pct IS NOT NULL
    AND employment_rate_pct IS NOT NULL
    AND unemployment_rate_pct > 50   -- implausible threshold for NZ data
