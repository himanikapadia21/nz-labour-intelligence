"""
load_to_snowflake.py
────────────────────
Loads DataFrames into Snowflake RAW schema.

Strategy: TRUNCATE + INSERT (full refresh each run).
This is appropriate for government statistics data where the source
publishes revised historical data in each release.

For append-only sources (e.g. real-time data), switch to MERGE/UPSERT.

Features:
  - Uses Snowflake stage (internal) for bulk loading — much faster than row-by-row
  - Automatic table creation if not exists
  - Load metadata tracking in _INGESTION_LOG table
  - Connection pooling via context manager
"""

from contextlib import contextmanager
from datetime import datetime, timezone

import pandas as pd
import snowflake.connector
from loguru import logger
from snowflake.connector.pandas_tools import write_pandas

from config import SNOWFLAKE, TABLE_SCHEMAS


# ── Connection ─────────────────────────────────────────────────────────────────

@contextmanager
def get_snowflake_connection():
    """
    Context manager for Snowflake connections.
    Ensures connections are always closed, even on error.
    """
    conn = snowflake.connector.connect(
        account=SNOWFLAKE["account"],
        user=SNOWFLAKE["user"],
        password=SNOWFLAKE["password"],
        role=SNOWFLAKE["role"],
        warehouse=SNOWFLAKE["warehouse"],
        database=SNOWFLAKE["database"],
        schema=SNOWFLAKE["schema"],
        # Connection settings for reliability
        login_timeout=30,
        network_timeout=120,
        session_parameters={
            "QUERY_TAG": "NZ_LABOUR_PIPELINE",
            "TIMEZONE": "Pacific/Auckland",
        },
    )
    try:
        logger.info("Snowflake connection established")
        yield conn
    finally:
        conn.close()
        logger.info("Snowflake connection closed")


# ── Table management ───────────────────────────────────────────────────────────

def _ensure_table_exists(cur, table_name: str) -> None:
    """
    Create the target table if it doesn't exist.
    Uses IF NOT EXISTS — idempotent and safe to run repeatedly.
    """
    schema = TABLE_SCHEMAS.get(table_name)
    if not schema:
        raise ValueError(f"No schema defined for table: {table_name}")

    ddl = f"""
        CREATE TABLE IF NOT EXISTS {SNOWFLAKE['database']}.{SNOWFLAKE['schema']}.{table_name} (
            {schema}
        )
        COMMENT = 'Raw data ingested from Stats NZ. Do not modify directly.'
    """
    cur.execute(ddl)
    logger.info(f"Table ready: {table_name}")


def _ensure_log_table_exists(cur) -> None:
    """Create the ingestion audit log table."""
    cur.execute("""
        CREATE TABLE IF NOT EXISTS _INGESTION_LOG (
            log_id          INTEGER AUTOINCREMENT PRIMARY KEY,
            table_name      VARCHAR(100),
            run_timestamp   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
            rows_loaded     INTEGER,
            source_files    VARCHAR(500),
            status          VARCHAR(20),
            error_message   VARCHAR(2000),
            duration_secs   FLOAT
        )
        COMMENT = 'Audit log for all pipeline runs.'
    """)


# ── Loading ────────────────────────────────────────────────────────────────────

def _truncate_table(cur, table_name: str) -> None:
    """Truncate before full refresh load."""
    cur.execute(f"TRUNCATE TABLE IF EXISTS {table_name}")
    logger.info(f"Truncated: {table_name}")


def load_dataframe_to_snowflake(
    df: pd.DataFrame,
    table_name: str,
    conn,
    source_files: str = "",
) -> int:
    """
    Load a DataFrame to a Snowflake table using write_pandas (bulk copy).

    write_pandas creates a temporary internal stage, uploads a parquet file,
    then COPYs it into the table. Far faster than executemany() for large data.

    Returns number of rows loaded.
    """
    start = datetime.now(timezone.utc)
    cur = conn.cursor()

    try:
        _ensure_table_exists(cur, table_name)
        _truncate_table(cur, table_name)

        # write_pandas requires uppercase column names
        df_upload = df.copy()
        df_upload.columns = [c.upper() for c in df_upload.columns]

        # Add ingestion timestamp
        df_upload["_INGESTED_AT"] = datetime.now(timezone.utc)
        df_upload["_SOURCE_FILE"] = source_files

        success, n_chunks, n_rows, output = write_pandas(
            conn=conn,
            df=df_upload,
            table_name=table_name,
            database=SNOWFLAKE["database"],
            schema=SNOWFLAKE["schema"],
            auto_create_table=False,   # We manage DDL ourselves
            overwrite=False,           # We already truncated
            quote_identifiers=False,
        )

        duration = (datetime.now(timezone.utc) - start).total_seconds()

        if success:
            logger.success(
                f"Loaded {n_rows:,} rows into {table_name} "
                f"({n_chunks} chunk(s), {duration:.1f}s)"
            )
            _log_run(cur, table_name, n_rows, source_files, "SUCCESS", None, duration)
        else:
            raise RuntimeError(f"write_pandas failed: {output}")

        conn.commit()
        return n_rows

    except Exception as e:
        _log_run(cur, table_name, 0, source_files, "FAILED", str(e)[:2000], 0)
        conn.commit()
        raise
    finally:
        cur.close()


def _log_run(cur, table_name, rows, source_files, status, error_msg, duration):
    """Write an entry to the ingestion audit log."""
    try:
        _ensure_log_table_exists(cur)
        cur.execute("""
            INSERT INTO _INGESTION_LOG
                (table_name, rows_loaded, source_files, status, error_message, duration_secs)
            VALUES (%s, %s, %s, %s, %s, %s)
        """, (table_name, rows, source_files, status, error_msg, duration))
    except Exception as log_err:
        logger.warning(f"Could not write to _INGESTION_LOG: {log_err}")


# ── Snowflake Advanced Features Setup ─────────────────────────────────────────

def setup_snowflake_advanced_features(conn) -> None:
    """
    Demonstrates Snowflake-specific features — run once after initial load.
    These are what differentiate your project from a basic SQL project.
    """
    cur = conn.cursor()

    # 1. Dynamic data masking on salary column
    logger.info("Setting up dynamic data masking...")
    cur.execute("""
        CREATE OR REPLACE MASKING POLICY wage_masking_policy
            AS (val FLOAT) RETURNS FLOAT ->
            CASE
                WHEN CURRENT_ROLE() IN ('ENGINEER_ROLE', 'ANALYST_ROLE') THEN val
                ELSE -1   -- REPORTER_ROLE sees -1 instead of actual wages
            END
        COMMENT = 'Masks raw wage values for reporter role'
    """)

    # Apply masking to the wages table
    cur.execute("""
        ALTER TABLE RAW_QES_WAGES
        MODIFY COLUMN DATA_VALUE
        SET MASKING POLICY wage_masking_policy
    """)

    # 2. Row access policy — reporters can only see national-level data
    logger.info("Setting up row access policy...")
    cur.execute("""
        CREATE OR REPLACE ROW ACCESS POLICY regional_access_policy
            AS (series_title_1 VARCHAR) RETURNS BOOLEAN ->
            CASE
                WHEN CURRENT_ROLE() IN ('ENGINEER_ROLE', 'ANALYST_ROLE') THEN TRUE
                WHEN CURRENT_ROLE() = 'REPORTER_ROLE'
                    THEN series_title_1 ILIKE '%New Zealand%'
                        OR series_title_1 ILIKE '%total%'
                ELSE FALSE
            END
        COMMENT = 'Reporters see only national-level rows'
    """)

    # 3. Create a zero-copy clone for development
    logger.info("Creating dev clone...")
    cur.execute("""
        CREATE DATABASE IF NOT EXISTS NZ_LABOUR_DB_DEV
        CLONE NZ_LABOUR_DB
        COMMENT = 'Zero-copy dev clone — costs nothing until data diverges'
    """)

    logger.success("Advanced Snowflake features configured")
    cur.close()


def demonstrate_time_travel(conn) -> None:
    """
    Shows Snowflake time travel — query the table as it was before the last load.
    Great for your portfolio README / interview explanation.
    """
    cur = conn.cursor()

    # Query data as it was 1 hour ago
    cur.execute("""
        SELECT COUNT(*) as row_count,
               MIN(period) as earliest_period,
               MAX(period) as latest_period
        FROM RAW_HLFS_EMPLOYMENT
            AT (OFFSET => -3600)   -- 1 hour ago in seconds
    """)
    result = cur.fetchone()
    logger.info(f"Time travel result (1hr ago): {result}")

    cur.close()
