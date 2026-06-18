# NZ Labour Market Intelligence Platform

End-to-end data pipeline ingesting 3M+ rows from Stats NZ into Snowflake, 
transformed via dbt (8 models, 57 tests passing), with RBAC security and 
automated GitHub Actions orchestration.

## Tech Stack
- **Ingestion:** Python + Stats NZ open data
- **Warehouse:** Snowflake (RBAC, secure views, time travel)
- **Transformation:** dbt Core (8 models, 57 tests)
- **Orchestration:** GitHub Actions (daily 7am NZT)
- **Visualisation:** Power BI

## dbt Lineage Graph
<img width="1877" height="867" alt="ss" src="https://github.com/user-attachments/assets/fb644adc-cb2d-4dde-8cbb-f93d33ba4b7c" />
