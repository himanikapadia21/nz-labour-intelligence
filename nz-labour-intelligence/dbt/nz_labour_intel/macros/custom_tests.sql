{% macro test_is_valid_rate(model, column_name, min_val=0, max_val=100) %}
/*
Custom generic test: test_is_valid_rate
────────────────────────────────────────
Tests that a rate/percentage column stays within realistic bounds.
More informative than dbt_expectations for Stats NZ data because it
returns the offending rows so you can inspect them.

Usage in schema.yml:
    - test_is_valid_rate:
        min_val: 0
        max_val: 100
*/

SELECT
    {{ column_name }},
    COUNT(*) AS failing_rows

FROM {{ model }}

WHERE {{ column_name }} IS NOT NULL
  AND ({{ column_name }} < {{ min_val }} OR {{ column_name }} > {{ max_val }})

GROUP BY 1

{% endmacro %}


{% macro test_no_future_periods(model, column_name) %}
/*
Custom generic test: test_no_future_periods
─────────────────────────────────────────────
Ensures no period dates are in the future (which would indicate
a data processing error — Stats NZ doesn't publish future quarters).
*/

SELECT
    {{ column_name }},
    COUNT(*) AS future_rows

FROM {{ model }}

WHERE {{ column_name }} > CURRENT_DATE()

GROUP BY 1

{% endmacro %}


{% macro safe_divide(numerator, denominator, default=0) %}
/*
Utility macro: safe_divide
───────────────────────────
Avoids division by zero errors in ratio calculations.
Usage: {{ safe_divide('numerator_col', 'denominator_col', 0) }}
*/

CASE
    WHEN {{ denominator }} IS NULL OR {{ denominator }} = 0 THEN {{ default }}
    ELSE {{ numerator }} / {{ denominator }}
END

{% endmacro %}


{% macro period_to_date(period_col, period_type='quarterly') %}
/*
Utility macro: period_to_date
──────────────────────────────
Converts Stats NZ period strings to dates.
period_type: 'quarterly' (2025Q4) or 'monthly' (2025M12)
*/

{% if period_type == 'quarterly' %}
    CASE RIGHT({{ period_col }}, 1)
        WHEN '1' THEN DATEADD('month',  0, TO_DATE(LEFT({{ period_col }}, 4) || '-01-01'))
        WHEN '2' THEN DATEADD('month',  3, TO_DATE(LEFT({{ period_col }}, 4) || '-01-01'))
        WHEN '3' THEN DATEADD('month',  6, TO_DATE(LEFT({{ period_col }}, 4) || '-01-01'))
        WHEN '4' THEN DATEADD('month',  9, TO_DATE(LEFT({{ period_col }}, 4) || '-01-01'))
    END
{% elif period_type == 'monthly' %}
    TRY_TO_DATE(
        LEFT({{ period_col }}, 4) || '-' ||
        LPAD(SUBSTRING({{ period_col }}, 6, 2), 2, '0') || '-01',
        'YYYY-MM-DD'
    )
{% endif %}

{% endmacro %}
