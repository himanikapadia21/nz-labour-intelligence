# Power BI Dashboard Setup

## Overview

Two report pages connecting to Snowflake `MART` schema via DirectQuery:

| Page | Mart Table | Purpose |
|------|-----------|---------|
| Regional Employment | `MART_REGIONAL_DASHBOARD` | Unemployment & employment rates by region |
| Wage Analysis | `MART_WAGE_ANALYSIS` + `MART_INDUSTRY_WAGES` | Private vs public wage trends, industry rankings |

---

## Step 1: Connect Power BI to Snowflake

1. Open Power BI Desktop → **Get Data** → **Snowflake**
2. Server: `<your_account>.snowflakecomputing.com`
3. Warehouse: `NZ_LABOUR_WH`
4. Data Connectivity mode: **DirectQuery** (always reflects latest Snowflake data)
5. Sign in as `REPORTER_ROLE` credentials
6. Select `NZ_LABOUR_DB` → schema `MART`
7. Import all three tables:
   - `MART_REGIONAL_DASHBOARD`
   - `MART_WAGE_ANALYSIS`
   - `MART_INDUSTRY_WAGES`

---

## Step 2: Data Model (Relationships)

In Power BI Model view, create these relationships:

```
MART_REGIONAL_DASHBOARD ──(PERIOD_START_DATE)──► MART_WAGE_ANALYSIS
MART_REGIONAL_DASHBOARD ──(PERIOD_START_DATE)──► MART_INDUSTRY_WAGES
```

Both relationships: many-to-one, single direction.

---

## Step 3: DAX Measures

Create a dedicated **Measures** table (New Table → `Measures = {}`), then add:

### KPI Cards

```dax
Latest Unemployment Rate =
CALCULATE(
    AVERAGE(MART_REGIONAL_DASHBOARD[UNEMPLOYMENT_RATE_PCT]),
    MART_REGIONAL_DASHBOARD[PERIOD_START_DATE] = MAX(MART_REGIONAL_DASHBOARD[PERIOD_START_DATE])
)

Latest Employment Rate =
CALCULATE(
    AVERAGE(MART_REGIONAL_DASHBOARD[EMPLOYMENT_RATE_PCT]),
    MART_REGIONAL_DASHBOARD[PERIOD_START_DATE] = MAX(MART_REGIONAL_DASHBOARD[PERIOD_START_DATE])
)

Estimated Annual Salary (NZD) =
CALCULATE(
    AVERAGE(MART_WAGE_ANALYSIS[ESTIMATED_ANNUAL_SALARY_NZD]),
    MART_WAGE_ANALYSIS[PERIOD_START_DATE] = MAX(MART_WAGE_ANALYSIS[PERIOD_START_DATE])
)
```

### Trend Measures

```dax
Unemployment Rate YoY Change (pp) =
VAR CurrentDate = MAX(MART_REGIONAL_DASHBOARD[PERIOD_START_DATE])
VAR PriorYearDate = EDATE(CurrentDate, -12)
VAR CurrentRate =
    CALCULATE(
        AVERAGE(MART_REGIONAL_DASHBOARD[UNEMPLOYMENT_RATE_PCT]),
        MART_REGIONAL_DASHBOARD[PERIOD_START_DATE] = CurrentDate
    )
VAR PriorRate =
    CALCULATE(
        AVERAGE(MART_REGIONAL_DASHBOARD[UNEMPLOYMENT_RATE_PCT]),
        MART_REGIONAL_DASHBOARD[PERIOD_START_DATE] = PriorYearDate
    )
RETURN
    IF(NOT ISBLANK(PriorRate), CurrentRate - PriorRate)

Regional vs National Gap =
AVERAGE(MART_REGIONAL_DASHBOARD[UNEMPLOYMENT_RATE_VS_NZ_PP])
```

### Wage Measures

```dax
Wage Growth Status =
VAR GrowthPct = AVERAGE(MART_WAGE_ANALYSIS[ALL_SECTORS_WAGE_YOY_GROWTH_PCT])
RETURN
    IF(GrowthPct >= 5,   "Strong (5%+)",
    IF(GrowthPct >= 2.5, "Moderate (2.5-5%)",
    IF(GrowthPct >= 0,   "Slow (0-2.5%)",
    IF(NOT ISBLANK(GrowthPct), "Declining", BLANK()))))

Public Sector Premium % =
AVERAGE(MART_WAGE_ANALYSIS[PUBLIC_PREMIUM_PCT])

Private vs Public Wage Gap (NZD) =
AVERAGE(MART_WAGE_ANALYSIS[PUBLIC_VS_PRIVATE_GAP_NZD])
```

---

## Step 4: Report Pages

### Page 1 — Regional Employment Dashboard

| Visual | Type | Fields |
|--------|------|--------|
| NZ Map (filled) | ArcGIS / Shape Map | Region → fill by `UNEMPLOYMENT_RATE_PCT` |
| Line chart | Line | X: `PERIOD_START_DATE`, Y: `UNEMPLOYMENT_RATE_PCT` + `NZ_UNEMPLOYMENT_RATE_PCT` |
| Bar chart | Clustered bar | Y: Region, X: `EMPLOYMENT_RATE_PCT` |
| KPI card | Card | `Latest Unemployment Rate` |
| KPI card | Card | `Unemployment Rate YoY Change (pp)` |
| Table | Table | Region, Employment Rate, Unemployment Rate, vs NZ Gap |
| Slicer | Dropdown | `REGION` |
| Slicer | Date range | `PERIOD_START_DATE` |

**Conditional formatting on bar chart:**
- `UNEMPLOYMENT_RATE_VS_NZ_PP` > +1 → Red background
- `UNEMPLOYMENT_RATE_VS_NZ_PP` between -1 and +1 → Yellow
- `UNEMPLOYMENT_RATE_VS_NZ_PP` < -1 → Green

### Page 2 — Wage Analysis

| Visual | Type | Fields |
|--------|------|--------|
| Line chart | Line | X: `PERIOD_START_DATE`, Y: `PRIVATE_HOURLY_WAGE_NZD` + `PUBLIC_HOURLY_WAGE_NZD` |
| Bar chart | Sorted bar | Y: `INDUSTRY_ANZSIC`, X: `AVG_HOURLY_WAGE_NZD` (from `MART_INDUSTRY_WAGES`) |
| KPI card | Card | `Estimated Annual Salary (NZD)` |
| KPI card | Card | `Public Sector Premium %` |
| KPI card | Card | `Wage Growth Status` |
| Line chart | Line | X: `PERIOD_START_DATE`, Y: `ALL_SECTORS_WAGE_YOY_GROWTH_PCT` |
| Slicer | Dropdown | Year (derived from `PERIOD_START_DATE`) |

**Conditional formatting on wage growth line:**
- Values ≥ 5 → Green
- Values 0–5 → Amber
- Values < 0 → Red

---

## Step 5: Scheduled Refresh

Set Power BI scheduled refresh to run **after** the GitHub Actions pipeline completes:
- Pipeline runs: `0 19 * * *` UTC (= 7am NZST)
- Power BI refresh: 8am NZST daily

In Power BI Service → Dataset → Settings → Scheduled Refresh:
- Frequency: Daily
- Time: 8:00 AM (New Zealand Standard Time)

---

## Row-Level Security (RLS) note

The `REPORTER_ROLE` in Snowflake already enforces:
- **Column masking**: raw `DATA_VALUE` in QES wages table shows `-1` for this role
- **Row access policy**: only national-level rows visible in raw tables

The mart tables (`MART_REGIONAL_DASHBOARD`, `MART_WAGE_ANALYSIS`) are pre-aggregated
and safe to expose — no masking needed at the Power BI layer for this project.

If you add user-level filtering in Power BI (e.g., by region per user), configure
Power BI RLS rules on top of the mart tables separately.
