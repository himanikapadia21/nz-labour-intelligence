# 🇳🇿 NZ Labour Market Intelligence Platform

> An end-to-end modern data stack project — ingesting real New Zealand government employment and wage data into Snowflake, transforming with dbt, and visualising through an interactive Streamlit dashboard with dark mode and narrative storytelling.

[![GitHub Actions](https://img.shields.io/badge/Automated-Daily%207am%20NZT-green?style=flat&logo=github)](https://github.com/himanikapadia21/nz-labour-intelligence/actions)
[![Snowflake](https://img.shields.io/badge/Snowflake-Data%20Warehouse-29B5E8?style=flat&logo=snowflake)](https://snowflake.com)
[![dbt](https://img.shields.io/badge/dbt-8%20Models%20%7C%2057%20Tests-FF694B?style=flat&logo=dbt)](https://getdbt.com)
[![Streamlit](https://img.shields.io/badge/Streamlit-Live%20Dashboard-FF4B4B?style=flat&logo=streamlit)](https://streamlit.io)

---

## 📸 Project Screenshot

![dbt Lineage Graph](assets/lineage_graph.png)
*dbt lineage graph — from raw Stats NZ sources through staging and intermediate layers to Power BI-ready mart models*

---

## 🎯 What This Project Does

**The problem:** Stats NZ publishes labour market data quarterly — employment rates, unemployment rates, wage data by region and industry. But it comes as messy ZIP files with millions of rows that are impossible to analyse without a proper data pipeline.

**The solution:** I built an automated pipeline that:

1. **Downloads** raw CSV files from Stats NZ every morning automatically
2. **Cleans and loads** 3 million+ rows into Snowflake
3. **Transforms** raw data into analytical models using dbt
4. **Tests** data quality with 57 automated checks
5. **Visualises** insights in an interactive Streamlit dashboard

**The result:** Anyone can open the dashboard and instantly answer questions like:
- Which NZ region has the highest unemployment right now?
- Are public sector wages growing faster than private sector?
- How has Auckland's labour market changed since COVID?

---

## 🏗️ Architecture

```
Stats NZ (open data)
        │
        ▼
  Python Pipeline          ← Downloads ZIPs, cleans CSVs, bulk loads to Snowflake
        │
        ▼
  Snowflake RAW            ← 3 tables, 3M+ rows, RBAC security, masking policies
        │
        ▼
  dbt Staging              ← Cleans types, parses periods, decodes dimensions
        │
        ▼
  dbt Intermediate         ← Business logic, YoY calculations, regional pivots
        │
        ▼
  dbt Mart                 ← Wide tables optimised for dashboards
        │
        ▼
  Streamlit Dashboard      ← Dark mode, interactive, narrative storytelling
        │
        ▼
  GitHub Actions           ← Runs the full pipeline daily at 7am NZT
```

---

## 📊 Data Sources

All data is free and publicly available from [Stats NZ](https://www.stats.govt.nz):

| Dataset | Description | Frequency | Rows |
|---------|-------------|-----------|------|
| HLFS (Household Labour Force Survey) | Employment rate, unemployment rate, participation rate by region, age, sex, ethnicity | Quarterly | ~1.5M |
| QES (Quarterly Employment Survey) | Average hourly and weekly earnings by industry and sector | Quarterly | ~200K |
| LCI (Labour Cost Index) | Wage inflation index — private vs public sector | Quarterly | ~33K |
| Employment Indicators | Monthly filled jobs and gross earnings by industry and region | Monthly | ~34K |

---

## 🛠️ Tech Stack

| Layer | Tool | Why |
|-------|------|-----|
| Ingestion | Python 3.11 | Handles ZIP extraction, normalisation, bulk loading |
| Warehouse | Snowflake | Auto-suspend, zero-copy cloning, time travel, RBAC |
| Transform | dbt Core | Lineage tracking, testing framework, documentation |
| Orchestration | GitHub Actions | Free, reliable, runs daily without any manual effort |
| Visualisation | Streamlit + Plotly | Interactive, dark mode, deployable as public URL |

---

## ❄️ Snowflake Features Demonstrated

This project goes beyond basic SQL to showcase production-grade Snowflake features:

- **RBAC** — 3-tier role hierarchy (ENGINEER → ANALYST → REPORTER) with least-privilege access
- **Secure Views** — Role-based data masking (REPORTER role sees -1 instead of actual wages)
- **Row-level security** — REPORTER role only sees national-level data, not regional breakdowns
- **Zero-copy cloning** — Instant dev environment clone (`NZ_LABOUR_DB_DEV`) at no extra cost
- **Time Travel** — Query historical data up to 7 days back for debugging bad loads
- **Resource Monitor** — Auto-suspends warehouse at 5 credits/month to prevent cost overruns
- **write_pandas bulk load** — Loads 3M rows via internal stage in under 2 minutes

---

## 🧪 dbt Models

```
models/
├── staging/                    ← Views — light cleaning, type casting
│   ├── stg_hlfs_employment     Parses period strings, decodes dimensions
│   ├── stg_qes_wages           Cleans wage data, derives sector labels
│   └── stg_employment_indicators  Parses monthly periods, scales values
│
├── intermediate/               ← Tables — business logic
│   ├── int_regional_employment Pivots long-format series into KPI columns
│   └── int_wage_trends         YoY growth via LAG, rolling averages, sector gap
│
└── mart/                       ← Tables — dashboard-ready
    ├── mart_regional_dashboard  One row per region per quarter, all KPIs + benchmarks
    ├── mart_wage_analysis       Sector wage comparison, growth categories
    └── mart_industry_wages      Industry wage rankings with percentiles
```

**Test results: 57/57 PASS** ✅

Tests include: not_null constraints, accepted_values, range validations (dbt_expectations), regex format checks, and two custom singular tests:
- `assert_unemployment_never_exceeds_employment` — logical sanity check
- `assert_wages_positive` — data quality guard

---

## 📱 Streamlit Dashboard

The dashboard has 4 pages:

| Page | What it shows |
|------|--------------|
| 🏠 Overview | National KPIs, key story cards, regional bar chart |
| 🗺️ Regional Story | Pick any region — get narrative + trend chart + comparison |
| 💰 Wage Story | Public vs private wage gap, real wage analysis |
| 📈 Trends Over Time | Multi-region comparison from 2015 to present |

**Design:** Dark mode, Plotly interactive charts, narrative storytelling so non-technical users understand what the numbers mean.

---

## 🚀 How to Run This Project

### Prerequisites
- Python 3.11+
- Snowflake free trial account ([trial.snowflake.com](https://trial.snowflake.com))
- dbt Core: `pip install dbt-snowflake`

### Step 1 — Snowflake setup
Run the SQL scripts in your Snowflake worksheet in order:
```
snowflake/01_setup_roles_and_databases.sql
snowflake/02_create_staging_tables.sql
snowflake/03_rbac_and_security.sql
```

### Step 2 — Configure credentials
```bash
cp .env.example .env
# Fill in your Snowflake account, username, and password
```

### Step 3 — Run the ingestion pipeline
```bash
cd ingestion
pip install -r requirements.txt
python run_pipeline.py --setup-advanced
```

### Step 4 — Run dbt
```bash
cd dbt/nz_labour_intel
dbt deps
dbt run
dbt test
dbt docs generate && dbt docs serve   # View lineage graph at localhost:8080
```

### Step 5 — Launch the dashboard
```bash
streamlit run app.py
# Opens at localhost:8501
```

### Step 6 — Automate with GitHub Actions
Add 3 repository secrets: `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PASSWORD`

The pipeline runs automatically every day at 7am NZT. ✅

---

## 📁 Project Structure

```
nz-labour-intelligence/
├── .github/workflows/
│   └── daily_pipeline.yml       # Scheduled GitHub Actions
├── ingestion/
│   ├── config.py                # Data source URLs and Snowflake config
│   ├── extract.py               # Download and parse Stats NZ ZIPs
│   ├── load_to_snowflake.py     # Bulk load with audit logging
│   ├── run_pipeline.py          # Pipeline orchestrator
│   └── requirements.txt
├── snowflake/
│   ├── 01_setup_roles_and_databases.sql
│   ├── 02_create_staging_tables.sql
│   └── 03_rbac_and_security.sql
├── dbt/nz_labour_intel/
│   ├── models/staging/
│   ├── models/intermediate/
│   ├── models/mart/
│   ├── macros/                  # Custom reusable SQL macros
│   └── tests/                   # Custom singular tests
├── app.py                       # Streamlit dashboard
└── .env.example                 # Credentials template
```

---

## 💡 Key Insights From the Data (March 2026)

- **Auckland** has the highest unemployment at **6.3%** — above the national average of 5.3%
- **Otago** has the lowest at **2.8%** — driven by Queenstown tourism and Dunedin's tech sector
- **Public sector** workers earn ~10% more per hour than private sector workers
- **Real wage growth** is essentially flat — nominal growth of 3.1% matches CPI inflation of 3.1%
- **Youth unemployment** (15-24 years) is 3x the national average at **16-17%**

---

## 👩‍💻 About

**Himani Kapadia**
Master of Computer and Information Sciences — Auckland University of Technology (AUT)
Student ID: 25317228

- GitHub: [himanikapadia21](https://github.com/himanikapadia21)
- Built as a portfolio project targeting NZ data engineering roles at Datacom, Accenture NZ, ASB Bank, and similar

---

## 📄 License

Data sourced from [Stats NZ](https://www.stats.govt.nz) under the [Creative Commons Attribution 4.0 International licence](https://creativecommons.org/licenses/by/4.0/).
