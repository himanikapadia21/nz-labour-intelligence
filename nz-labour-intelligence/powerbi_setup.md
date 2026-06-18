# Power BI Setup Guide
## Connecting to Snowflake + Key DAX Measures

### Step 1: Connect Power BI to Snowflake

1. Open Power BI Desktop → **Get Data** → **Snowflake**
2. Enter your Snowflake server: `your_account.snowflakecomputing.com`
3. Warehouse: `NZ_LABOUR_WH`
4. Login with your `REPORTER_ROLE` credentials
5. Select database `NZ_LABOUR_DB` → schema `MART`
6. Import both tables:
   - `MART_REGIONAL_DASHBOARD`
   - `MART_WAGE_ANALYSIS`

**Use DirectQuery mode** — data always reflects the latest Snowflake data.  
Set scheduled refresh to match your GitHub Actions schedule (daily at 7am NZT).

---

### Step 2: Data Model in Power BI

Create a relationship between the two mart tables on `PERIOD_START_DATE`.

```
MART_REGIONAL_DASHBOARD ──(PERIOD_START_DATE)── MART_WAGE_ANALYSIS
```

---

### Step 3: DAX Measures

Paste these into Power BI's DAX formula bar (New Measure):

```dax
-- Current unemployment rate (latest quarter)
Latest Unemployment Rate =
CALCULATE(
    AVERAGE(MART_REGIONAL_DASHBOARD[UNEMPLOYMENT_RATE_PCT]),
    MART_REGIONAL_DASHBOARD[PERIOD_START_DATE] = MAX(MART_REGIONAL_DASHBOARD[PERIOD_START_DATE])
)

-- YoY change in unemployment (latest quarter vs same quarter 1yr ago)
Unemployment Rate YoY Change (pp) =
VAR CurrentDate = MAX(MART_REGIONAL_DASHBOARD[PERIOD_START_DATE])
VAR PreviousYearDate = EDATE(CurrentDate, -12)
VAR CurrentRate = CALCULATE(
    AVERAGE(MART_REGIONAL_DASHBOARD[UNEMPLOYMENT_RATE_PCT]),
    MART_REGIONAL_DASHBOARD[PERIOD_START_DATE] = CurrentDate
)
VAR PreviousRate = CALCULATE(
    AVERAGE(MART_REGIONAL_DASHBOARD[UNEMPLOYMENT_RATE_PCT]),
    MART_REGIONAL_DASHBOARD[PERIOD_START_DATE] = PreviousYearDate
)
RETURN CurrentRate - PreviousRate

-- Regional unemployment vs national (how many pp above/below NZ average)
Regional vs National Gap =
AVERAGE(MART_REGIONAL_DASHBOARD[UNEMPLOYMENT_RATE_VS_NZ_PP])

-- Wage growth status label for card visual
Wage Growth Status =
VAR GrowthPct = AVERAGE(MART_WAGE_ANALYSIS[ALL_SECTORS_WAGE_YOY_GROWTH_PCT])
RETURN
    IF(GrowthPct >= 5, "🟢 Strong",
    IF(GrowthPct >= 2.5, "🟡 Moderate",
    IF(GrowthPct >= 0, "🟠 Slow",
    "🔴 Declining")))

-- Public sector premium (% more than private)
Public Sector Premium % =
AVERAGE(MART_WAGE_ANALYSIS[PUBLIC_PREMIUM_PCT])

-- Estimated annual salary (all sectors, latest quarter)
Estimated Annual Salary (NZD) =
CALCULATE(
    AVERAGE(MART_WAGE_ANALYSIS[ESTIMATED_ANNUAL_SALARY_NZD]),
    MART_WAGE_ANALYSIS[PERIOD_START_DATE] = MAX(MART_WAGE_ANALYSIS[PERIOD_START_DATE])
)
```

---

### Step 4: Recommended Visuals

| Visual | Fields | Purpose |
|--------|--------|---------|
| Map (filled) | Region, Unemployment Rate | Regional heat map |
| Line chart | Period Start Date, Unemployment Rate, NZ Unemployment Rate | Region vs NZ trend |
| Bar chart | Region, Employment Rate % | Cross-region comparison |
| Card | Latest Unemployment Rate | KPI summary |
| Card | Wage Growth Status | Wage KPI |
| Line chart | Period Start Date, Private Wage, Public Wage | Wage gap trend |
| Slicer | Region | Filter by region |
| Slicer | Year | Filter by year |

---

### Step 5: Conditional Formatting

For the unemployment bar chart, add conditional formatting:
- Background colour based on `UNEMPLOYMENT_RATE_VS_NZ_PP`
  - Red: > +1 percentage point above national
  - Yellow: -1 to +1 pp
  - Green: > 1 pp below national

This makes it immediately obvious which regions are underperforming.
