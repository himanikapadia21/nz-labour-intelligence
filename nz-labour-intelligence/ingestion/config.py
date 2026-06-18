"""
config.py
─────────
Central configuration for the NZ Labour Intelligence ingestion pipeline.
All values read from environment variables (set in .env or GitHub Secrets).
"""

import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

# ── Paths ──────────────────────────────────────────────────────────────────────
BASE_DIR = Path(__file__).parent
DATA_DIR = Path(os.getenv("DATA_DIR", BASE_DIR / "data" / "raw"))
DATA_DIR.mkdir(parents=True, exist_ok=True)

# ── Snowflake ──────────────────────────────────────────────────────────────────
SNOWFLAKE = {
    "account":   os.getenv("SNOWFLAKE_ACCOUNT"),
    "user":      os.getenv("SNOWFLAKE_USER"),
    "password":  os.getenv("SNOWFLAKE_PASSWORD"),
    "role":      os.getenv("SNOWFLAKE_ROLE",      "ENGINEER_ROLE"),
    "warehouse": os.getenv("SNOWFLAKE_WAREHOUSE", "NZ_LABOUR_WH"),
    "database":  os.getenv("SNOWFLAKE_DATABASE",  "NZ_LABOUR_DB"),
    "schema":    os.getenv("SNOWFLAKE_SCHEMA",    "RAW"),
}

# ── Stats NZ data sources ──────────────────────────────────────────────────────
# Stats NZ closed their REST API in Aug 2024.
# Data is now fetched from their public CSV bulk-download page.
# These URLs are stable — Stats NZ updates the files in-place each quarter.

STATS_NZ_SOURCES = [
    {
        "name":     "hlfs_employment",
        "url":      "https://www.stats.govt.nz/assets/Uploads/Labour-market-statistics/Labour-market-statistics-March-2026-quarter/Download-data/labour-market-statistics-march-2026-quarter.zip",
        "filename": "hlfs_employment.zip",
        "target_table": "RAW_HLFS_EMPLOYMENT",
        "description": "Household Labour Force Survey — employment/unemployment rates by region, age, sex",
    },
    {
        "name":     "qes_wages",
        "url":      "https://www.stats.govt.nz/assets/Uploads/Labour-market-statistics/Labour-market-statistics-March-2026-quarter/Download-data/labour-market-statistics-march-2026-quarter.zip",
        "filename": "qes_wages.zip",
        "target_table": "RAW_QES_WAGES",
        "description": "Quarterly Employment Survey — average hourly/weekly earnings by industry",
    },
    {
        "name":     "employment_indicators",
        "url":      "https://www.stats.govt.nz/assets/Uploads/Employment-indicators/Employment-indicators-April-2026/Download-data/employment-indicators-april-2026.zip",
        "filename": "employment_indicators.zip",
        "target_table": "RAW_EMPLOYMENT_INDICATORS",
        "description": "Monthly filled jobs and gross earnings by industry and region",
    },
]

# Snowflake table definitions — column names mapped from Stats NZ CSV headers
TABLE_SCHEMAS = {
    "RAW_HLFS_EMPLOYMENT": """
        series_reference    VARCHAR(60),
        period              VARCHAR(20),
        data_value          FLOAT,
        suppressed          VARCHAR(10),
        status              VARCHAR(30),
        units               VARCHAR(40),
        magnitude           INTEGER,
        subject             VARCHAR(100),
        group_name          VARCHAR(100),
        series_title_1      VARCHAR(200),
        series_title_2      VARCHAR(200),
        series_title_3      VARCHAR(200),
        series_title_4      VARCHAR(200),
        series_title_5      VARCHAR(200),
        _ingested_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
        _source_file        VARCHAR(200)
    """,
    "RAW_QES_WAGES": """
        series_reference    VARCHAR(60),
        period              VARCHAR(20),
        data_value          FLOAT,
        suppressed          VARCHAR(10),
        status              VARCHAR(30),
        units               VARCHAR(40),
        magnitude           INTEGER,
        subject             VARCHAR(100),
        group_name          VARCHAR(100),
        series_title_1      VARCHAR(200),
        series_title_2      VARCHAR(200),
        series_title_3      VARCHAR(200),
        series_title_4      VARCHAR(200),
        series_title_5      VARCHAR(200),
        _ingested_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
        _source_file        VARCHAR(200)
    """,
    "RAW_EMPLOYMENT_INDICATORS": """
        series_reference    VARCHAR(60),
        period              VARCHAR(20),
        data_value          FLOAT,
        suppressed          VARCHAR(10),
        status              VARCHAR(30),
        units               VARCHAR(40),
        magnitude           INTEGER,
        subject             VARCHAR(100),
        group_name          VARCHAR(100),
        series_title_1      VARCHAR(200),
        series_title_2      VARCHAR(200),
        series_title_3      VARCHAR(200),
        series_title_4      VARCHAR(200),
        series_title_5      VARCHAR(200),
        _ingested_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
        _source_file        VARCHAR(200)
    """,
}
