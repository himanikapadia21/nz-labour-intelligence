-- Singular test: assert_wages_positive
-- ──────────────────────────────────────
-- All hourly wages in the mart must be positive NZD values.
-- Negative or zero wages indicate a masking policy leak
-- (REPORTER_ROLE sees -1 via the dynamic masking policy) or a data error.

SELECT
    period_start_date,
    private_hourly_wage_nzd,
    public_hourly_wage_nzd,
    all_sectors_hourly_wage_nzd

FROM {{ ref('mart_wage_analysis') }}

WHERE
    private_hourly_wage_nzd <= 0
    OR public_hourly_wage_nzd <= 0
    OR all_sectors_hourly_wage_nzd <= 0
