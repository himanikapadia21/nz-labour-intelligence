"""
run_pipeline.py
───────────────
Entry point for the NZ Labour Intelligence ingestion pipeline.

Run manually:   python run_pipeline.py
Run via CI/CD:  called by GitHub Actions daily schedule

Exit codes:
  0 — success
  1 — partial failure (some sources failed, others succeeded)
  2 — total failure
"""

import sys
from datetime import datetime, timezone

from loguru import logger

from config import STATS_NZ_SOURCES
from extract import extract_all_sources
from load_to_snowflake import (
    get_snowflake_connection,
    load_dataframe_to_snowflake,
    setup_snowflake_advanced_features,
)


def configure_logging():
    logger.remove()
    logger.add(
        sys.stdout,
        format="<green>{time:HH:mm:ss}</green> | <level>{level: <8}</level> | {message}",
        level="INFO",
    )
    logger.add(
        "logs/pipeline_{time:YYYY-MM-DD}.log",
        rotation="1 day",
        retention="7 days",
        level="DEBUG",
    )


def run_pipeline(setup_advanced: bool = False) -> int:
    """
    Full pipeline: extract → load → (optional) advanced setup.
    Returns exit code.
    """
    configure_logging()
    start_time = datetime.now(timezone.utc)
    logger.info("=" * 60)
    logger.info("NZ Labour Market Intelligence — Ingestion Pipeline")
    logger.info(f"Start: {start_time.strftime('%Y-%m-%d %H:%M:%S UTC')}")
    logger.info("=" * 60)

    # ── Step 1: Extract ────────────────────────────────────────────────────────
    logger.info("STEP 1: Extracting data from Stats NZ...")
    try:
        source_data = extract_all_sources()
    except Exception as e:
        logger.error(f"Extract failed completely: {e}")
        return 2

    # ── Step 2: Load to Snowflake ──────────────────────────────────────────────
    logger.info("STEP 2: Loading to Snowflake...")
    success_count = 0
    fail_count = 0

    source_table_map = {s["name"]: s["target_table"] for s in STATS_NZ_SOURCES}

    try:
        with get_snowflake_connection() as conn:
            for source_name, df in source_data.items():
                table_name = source_table_map.get(source_name)
                if not table_name:
                    logger.warning(f"No table mapping for source: {source_name}")
                    continue

                try:
                    rows = load_dataframe_to_snowflake(
                        df=df,
                        table_name=table_name,
                        conn=conn,
                        source_files=source_name,
                    )
                    logger.success(f"✅ {source_name} → {table_name}: {rows:,} rows")
                    success_count += 1

                except Exception as e:
                    logger.error(f"❌ Failed to load {source_name}: {e}")
                    fail_count += 1

            # ── Step 3: Advanced features (first run only) ─────────────────────
            if setup_advanced:
                logger.info("STEP 3: Setting up advanced Snowflake features...")
                try:
                    setup_snowflake_advanced_features(conn)
                    logger.success("✅ Advanced features configured")
                except Exception as e:
                    logger.warning(f"Advanced features setup failed (non-fatal): {e}")

    except Exception as e:
        logger.error(f"Snowflake connection failed: {e}")
        return 2

    # ── Summary ────────────────────────────────────────────────────────────────
    duration = (datetime.now(timezone.utc) - start_time).total_seconds()
    logger.info("=" * 60)
    logger.info(f"Pipeline complete in {duration:.1f}s")
    logger.info(f"  ✅ Succeeded: {success_count}")
    logger.info(f"  ❌ Failed:    {fail_count}")
    logger.info("=" * 60)

    if fail_count == 0:
        return 0
    elif success_count > 0:
        return 1
    else:
        return 2


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="NZ Labour Intelligence Pipeline")
    parser.add_argument(
        "--setup-advanced",
        action="store_true",
        help="Set up RBAC, masking policies, time travel (run once after first load)",
    )
    args = parser.parse_args()

    exit_code = run_pipeline(setup_advanced=args.setup_advanced)
    sys.exit(exit_code)
