"""
extract.py
──────────
Downloads Stats NZ labour market CSV files.

Stats NZ publishes bulk CSV downloads for each quarterly release.
This module handles:
  - Downloading ZIP archives
  - Extracting the relevant CSV files
  - Light pre-processing (standardise column names, add metadata columns)
  - Returning clean DataFrames ready for Snowflake loading

Since Stats NZ doesn't have a public REST API anymore (closed Aug 2024),
we download the published ZIP files directly. URLs are updated in config.py
each quarter — a one-line change.
"""

import io
import zipfile
from pathlib import Path

import pandas as pd
import requests
from loguru import logger
from tenacity import retry, stop_after_attempt, wait_exponential

from config import DATA_DIR, STATS_NZ_SOURCES


# ── Column name normalisation ──────────────────────────────────────────────────
# Stats NZ uses "Series_Reference", "Period", etc. — we lowercase + snake_case
COLUMN_RENAMES = {
    "Series_reference": "series_reference",
    "Series Reference": "series_reference",
    "Period":           "period",
    "Data_value":       "data_value",
    "Data value":       "data_value",
    "Suppressed":       "suppressed",
    "STATUS":           "status",
    "Status":           "status",
    "UNITS":            "units",
    "Units":            "units",
    "Magnitude":        "magnitude",
    "Subject":          "subject",
    "Group":            "group_name",
    "Series_title_1":   "series_title_1",
    "Series_title_2":   "series_title_2",
    "Series_title_3":   "series_title_3",
    "Series_title_4":   "series_title_4",
    "Series_title_5":   "series_title_5",
}

EXPECTED_COLUMNS = [
    "series_reference", "period", "data_value", "suppressed",
    "status", "units", "magnitude", "subject", "group_name",
    "series_title_1", "series_title_2", "series_title_3",
    "series_title_4", "series_title_5",
]


@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=2, min=4, max=30),
    reraise=True,
)
def _download_file(url: str, dest_path: Path) -> None:
    """Download a file with retry logic. Streams to avoid memory issues."""
    logger.info(f"Downloading: {url}")
    with requests.get(url, stream=True, timeout=120) as r:
        r.raise_for_status()
        total = int(r.headers.get("content-length", 0))
        downloaded = 0
        with open(dest_path, "wb") as f:
            for chunk in r.iter_content(chunk_size=8192):
                f.write(chunk)
                downloaded += len(chunk)
    logger.info(f"Downloaded {downloaded:,} bytes → {dest_path.name}")


def _extract_csv_from_zip(zip_path: Path, source_name: str) -> pd.DataFrame:
    """
    Extract the main data CSV from a Stats NZ ZIP archive.
    Stats NZ ZIPs typically contain multiple CSVs — we want the one
    with the actual time-series data (not the metadata/footnotes file).
    """
    frames = []
    with zipfile.ZipFile(zip_path, "r") as zf:
        csv_files = [f for f in zf.namelist() if f.endswith(".csv")]
        logger.debug(f"Found CSV files in zip: {csv_files}")

        for csv_name in csv_files:
            # Skip footnotes/metadata files
            lower = csv_name.lower()
            if any(skip in lower for skip in ["footnote", "metadata", "notes"]):
                logger.debug(f"Skipping metadata file: {csv_name}")
                continue

            with zf.open(csv_name) as f:
                try:
                    df = pd.read_csv(f, dtype=str)
                    # Only keep files that look like time-series data
                    if "Period" in df.columns or "period" in df.columns:
                        frames.append((csv_name, df))
                        logger.info(f"Loaded {len(df):,} rows from {csv_name}")
                except Exception as e:
                    logger.warning(f"Could not read {csv_name}: {e}")

    if not frames:
        raise ValueError(f"No time-series CSV found in {zip_path.name}")

    # Concatenate if multiple data files in the ZIP
    dfs = []
    for csv_name, df in frames:
        df["_source_file"] = csv_name
        dfs.append(df)

    return pd.concat(dfs, ignore_index=True)


def _normalise_dataframe(df: pd.DataFrame, source_name: str) -> pd.DataFrame:
    """
    Standardise column names, add metadata columns, cast data types.
    """
    # Rename columns to snake_case
    df = df.rename(columns=COLUMN_RENAMES)

    # Add any missing expected columns as NULL
    for col in EXPECTED_COLUMNS:
        if col not in df.columns:
            df[col] = None

    # Keep only expected + metadata columns
    keep = EXPECTED_COLUMNS + ["_source_file"]
    df = df[[c for c in keep if c in df.columns]].copy()

    # Cast data types
    df["data_value"] = pd.to_numeric(df["data_value"], errors="coerce")
    df["magnitude"] = pd.to_numeric(df["magnitude"], errors="coerce").fillna(0).astype(int)

    # Strip whitespace from string columns
    str_cols = [c for c in df.columns if df[c].dtype == object]
    for col in str_cols:
        df[col] = df[col].str.strip()

    # Replace empty strings with None (maps to SQL NULL)
    df = df.replace({"": None, "..": None, "N/A": None})

    logger.info(f"Normalised {source_name}: {len(df):,} rows, {len(df.columns)} columns")
    return df


def extract_all_sources() -> dict[str, pd.DataFrame]:
    """
    Main extract function — downloads and processes all Stats NZ sources.
    Returns dict of {source_name: DataFrame}.
    """
    results = {}

    for source in STATS_NZ_SOURCES:
        name = source["name"]
        logger.info(f"─── Extracting: {name} ───")

        dest_path = DATA_DIR / source["filename"]

        try:
            # Download (skip if already downloaded today — cache for re-runs)
            if dest_path.exists():
                logger.info(f"Using cached file: {dest_path.name}")
            else:
                _download_file(source["url"], dest_path)

            # Extract CSV from ZIP
            df = _extract_csv_from_zip(dest_path, name)

            # Normalise
            df = _normalise_dataframe(df, name)

            results[name] = df

        except Exception as e:
            logger.error(f"Failed to extract {name}: {e}")
            raise

    logger.info(f"Extract complete — {len(results)} sources loaded")
    return results


if __name__ == "__main__":
    # Quick test — run standalone
    logger.info("Running extract standalone test...")
    data = extract_all_sources()
    for name, df in data.items():
        print(f"\n{name}: {df.shape}")
        print(df.head(3).to_string())
