# NZ Labour Market Intelligence Platform

> End-to-end modern data stack — ingesting public NZ employment & wage data from Stats NZ into Snowflake, transforming with dbt, and visualising in Power BI. Orchestrated daily with GitHub Actions.

![Pipeline](https://img.shields.io/badge/pipeline-GitHub%20Actions-2088FF?logo=github-actions&logoColor=white)
![Snowflake](https://img.shields.io/badge/warehouse-Snowflake-29B5E8?logo=snowflake&logoColor=white)
![dbt](https://img.shields.io/badge/transform-dbt-FF694B?logo=dbt&logoColor=white)
![Python](https://img.shields.io/badge/ingest-Python%203.11-3776AB?logo=python&logoColor=white)
![Power BI](https://img.shields.io/badge/viz-Power%20BI-F2C811?logo=powerbi&logoColor=black)

---

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌──────────────────────────────────────────────┐
│   Stats NZ      │     │  Python Ingest   │     │                 Snowflake                    │
│  (public CSVs)  │────►│  extract.py      │────►│                                              │
│                 │     │  load_to_        │     │  RAW schema            STAGING schema        │
│  HLFS quarterly │     │  snowflake.py    │     │  ┌──────────────┐    ┌──────────────┐       │
│  QES wages      │     │                  │     │  │RAW_HLFS_     │───►│stg_hlfs_     │       │
│  Monthly jobs   │     │  Retry + bulk    │     │  │EMPLOYMENT    │    │employment    │       │
│                 │     │  COPY via stage  │     │  │RAW_QES_WAGES │───►│stg_qes_wages │       │
└─────────────────┘     │  Audit log table │     │  │RAW_EMPLOY_   │───►│stg_employ_   │       │
                        └──────────────────┘     │  │INDICATORS    │    │indicators    │       │
                                                 │  └──────────────┘    └──────┬───────┘       │
                                                 │  RBAC · Masking · Time Travel│ dbt run      │
                                                 │  INTERMEDIATE schema          │              │
                                                 │  ┌─────────────────────────┐  │              │
                                                 │  │int_regional_employment  │◄─┘              │
                                                 │  │int_wage_trends          │                 │
                                                 │  └───────────┬─────────────┘                 │
                                                 │              │ dbt run                       │
                                                 │  MART schema │                               │
                                                 │  ┌───────────▼─────────────┐                 │
                                                 │  │mart_regional_dashboard  │                 │
                                                 │  │mart_wage_analysis       │                 │
                                                 │  │mart_industry_wages      │                 │
                                                 │  └─────────────────────────┘                 │
                                                 └────────────────────────┬─────────────────────┘
                                                                          │ DirectQuery
                                                               ┌──────────▼──────────┐
                                                               │      Power BI       │
                                                               │  Regional Dashboard │
                                                               │  Wage Analysis      │
                                                               └─────────────────────┘
```

**Orchestration:** GitHub Actions cron `0 19 * * *` UTC (= 7am NZST) → ingest → dbt run → dbt test → Slack alert on failure

---

## Tech Stack

| Layer | Tool | Purpose |
|-------|------|---------|
| Source | Stats NZ public bulk CSVs | NZ employment & wage statistics |
| Ingest | Python 3.11 + `snowflake-connector-python` | Download, clean, bulk-load to Snowflake |
| Warehouse | Snowflake (free trial compatible) | Storage, compute, RBAC, masking, time travel |
| Transform | dbt Core + dbt-snowflake | Staging → Intermediate → Mart model layers |
| Test | dbt generic tests + `dbt_expectations` | Null checks, range checks, regex, custom tests |
| Orchestrate | GitHub Actions (free tier) | Daily schedule, artifact upload, Slack alerting |
| Visualise | Power BI Desktop | Regional unemployment dashboard + wage analysis |

---

## Data Sources (Stats NZ — free, public)

| Dataset | Content | Frequency |
|---------|---------|-----------|
| HLFS (Household Labour Force Survey) | Employment rate, unemployment rate, participation rate by region, age, sex | Quarterly |
| QES (Quarterly Employment Survey) | Average hourly & weekly earnings by industry and sector | Quarterly |
| Employment Indicators | Filled jobs and gross earnings by industry and region | Monthly |

> Stats NZ closed their REST API in August 2024. Data is fetched from stable bulk-download ZIP URLs published with each release. Update the URLs in [ingestion/config.py](ingestion/config.py) when a new release drops — it's a one-line change per source.

---

## Snowflake Features Demonstrated

| Feature | File | What it shows |
|---------|------|---------------|
| RBAC — 3-tier role hierarchy | `snowflake/01_setup_roles_and_databases.sql` | Engineer → Analyst → Reporter with future grants |
| Dynamic Data Masking | `snowflake/03_rbac_and_security.sql` | REPORTER_ROLE sees `-1` instead of raw wages |
| Row Access Policy | `snowflake/03_rbac_and_security.sql` | Reporters see only national-level rows |
| Time Travel (AT/OFFSET) | `dbt/.../analyses/snowflake_time_travel_demo.sql` | Compare table state across time, UNDROP |
| Zero-Copy Cloning | `snowflake/03_rbac_and_security.sql` | Instant dev DB, no storage cost until diverged |
| Resource Monitor | `snowflake/03_rbac_and_security.sql` | Cost guardrail — suspend warehouse at 100% |
| Bulk COPY via stage | `ingestion/load_to_snowflake.py` | `write_pandas` uses internal stage for fast load |
| Cluster keys on `period` | `snowflake/02_create_staging_tables.sql` | Partition pruning for time-range queries |
| Query tags | `ingestion/load_to_snowflake.py` | Audit trail in `INFORMATION_SCHEMA.QUERY_HISTORY` |

---

## dbt Model Layers

```
models/
├── staging/           # 1:1 with source — rename, cast, derive period fields
│   ├── stg_hlfs_employment.sql        (quarterly: employment/unemployment rates)
│   ├── stg_qes_wages.sql              (quarterly: hourly/weekly earnings by sector)
│   ├── stg_employment_indicators.sql  (monthly: filled jobs + gross earnings)
│   └── schema.yml                     (source declarations + model tests)
├── intermediate/      # Business logic — pivots, window functions, joins
│   ├── int_regional_employment.sql    (HLFS + Employment Indicators pivoted to wide)
│   ├── int_wage_trends.sql            (YoY growth via LAG, rolling avg, sector pivot)
│   └── schema.yml
└── mart/              # Power BI-ready wide tables — denormalised, rounded
    ├── mart_regional_dashboard.sql    (grain: region + quarter)
    ├── mart_wage_analysis.sql         (grain: sector + quarter)
    ├── mart_industry_wages.sql        (grain: industry + quarter, with rankings)
    └── schema.yml
```

**Materialisations:** staging → `view` | intermediate + mart → `table`

**Custom generic tests** (`macros/custom_tests.sql`):
- `test_is_valid_rate` — validates rate columns stay within configurable min/max
- `test_no_future_periods` — rejects period dates beyond today

**Singular tests** (`tests/`):
- `assert_unemployment_never_exceeds_employment.sql`
- `assert_wages_positive.sql` — catches masking policy leaks

---

## Project Structure

```
nz-labour-intelligence/
├── .github/
│   └── workflows/
│       └── daily_pipeline.yml           # Cron: 7am NZST daily
├── ingestion/
│   ├── config.py                        # Snowflake + Stats NZ source URLs
│   ├── extract.py                       # Download, unzip, normalise CSVs
│   ├── load_to_snowflake.py             # Bulk load + masking + time travel demos
│   ├── run_pipeline.py                  # CLI entry point (--setup-advanced flag)
│   └── requirements.txt
├── snowflake/
│   ├── 01_setup_roles_and_databases.sql
│   ├── 02_create_staging_tables.sql
│   └── 03_rbac_and_security.sql
├── dbt/nz_labour_intel/
│   ├── dbt_project.yml
│   ├── packages.yml                     # dbt_utils + dbt_expectations
│   ├── profiles.yml                     # gitignored — reads env vars
│   ├── models/
│   │   ├── staging/
│   │   ├── intermediate/
│   │   └── mart/
│   ├── macros/
│   │   └── custom_tests.sql             # Generic tests + utility macros
│   ├── analyses/
│   │   └── snowflake_time_travel_demo.sql
│   └── tests/
│       ├── assert_unemployment_never_exceeds_employment.sql
│       └── assert_wages_positive.sql
├── powerbi/
│   └── README.md                        # Connection guide + DAX measures
├── .env.example                         # Copy to .env — fill in credentials
└── README.md
```

---

## Quick Start

### Prerequisites

- [Snowflake free trial](https://trial.snowflake.com) — ap-southeast-2 region recommended
- Python 3.11+
- `pip install dbt-snowflake`

### 1 — Clone and configure

```bash
git clone https://github.com/himanikapadia21/nz-labour-intelligence.git
cd nz-labour-intelligence
cp .env.example .env
# Edit .env — add SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_PASSWORD
```

### 2 — Set up Snowflake

In a Snowflake worksheet, run each file in order:

```
snowflake/01_setup_roles_and_databases.sql   # roles, warehouse, schemas
snowflake/02_create_staging_tables.sql       # raw tables + audit log
snowflake/03_rbac_and_security.sql           # masking, row access, resource monitor
```

### 3 — Ingest data

```bash
cd ingestion
pip install -r requirements.txt

# First run — also sets up masking policies and zero-copy dev clone
python run_pipeline.py --setup-advanced

# Daily runs
python run_pipeline.py
```

### 4 — Run dbt

```bash
cd dbt/nz_labour_intel
dbt deps           # install dbt_utils + dbt_expectations
dbt run            # build all models
dbt test           # run all tests
dbt docs generate
dbt docs serve     # opens lineage graph at http://localhost:8080
```

### 5 — Connect Power BI

See [powerbi/README.md](powerbi/README.md) for step-by-step connection, relationship model, DAX measures, and visual setup.

### 6 — GitHub Actions CI/CD

1. Push to GitHub
2. Add repository secrets: `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PASSWORD`
3. Optionally add `SLACK_WEBHOOK_URL` for failure alerts
4. Pipeline auto-runs at 7am NZST daily, or trigger manually via **Actions → Run workflow**

---

## Author

**Himani Kapadia** | AUT Master of Computer and Information Sciences
GitHub: [himanikapadia21](https://github.com/himanikapadia21)
