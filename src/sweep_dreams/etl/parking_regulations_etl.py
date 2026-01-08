"""
ETL script to load SF parking regulations CSV into Supabase.

Source: SF Open Data - Parking regulations (except non-metered color curb)
File: Parking_regulations_(except_non-metered_color_curb)_YYYYMMDD.csv
"""

import csv
import os
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

from dotenv import load_dotenv
from supabase import Client, create_client


# Regex to normalize "Time LImited" -> "Time limited", etc.
REGULATION_NORMALIZATIONS = {
    "time limited": "Time limited",
    "no parking any time": "No parking any time",
    "no oversized vehicles": "No oversized vehicles",
    "pay or permit": "Pay or Permit",
    "government permit": "Government permit",
    "limited no parking": "Limited No Parking",
    "no overnight parking": "No overnight parking",
}


def normalize_regulation(raw: str | None) -> str | None:
    """Normalize regulation type casing."""
    if not raw:
        return None
    lower = raw.strip().lower()
    return REGULATION_NORMALIZATIONS.get(lower, raw.strip())


def parse_int(value: str | None) -> int | None:
    """Parse an integer from a string, returning None for empty/invalid."""
    if not value or not value.strip():
        return None
    try:
        return int(value.strip())
    except ValueError:
        return None


def parse_float(value: str | None) -> float | None:
    """Parse a float from a string, returning None for empty/invalid."""
    if not value or not value.strip():
        return None
    try:
        return float(value.strip())
    except ValueError:
        return None


def parse_date(value: str | None) -> str | None:
    """Parse a date string into YYYY-MM-DD format."""
    if not value or not value.strip():
        return None

    # Try various formats
    formats = [
        "%m/%d/%Y",  # 7/19/2016
        "%Y-%m-%d",  # 2016-07-19
        "%Y/%m/%d",  # 2016/07/19
    ]

    for fmt in formats:
        try:
            dt = datetime.strptime(value.strip(), fmt)
            return dt.strftime("%Y-%m-%d")
        except ValueError:
            continue

    return None


def parse_timestamp(value: str | None) -> str | None:
    """Parse a timestamp string into ISO format."""
    if not value or not value.strip():
        return None

    # Example: "2024 Apr 29 05:21:10 PM"
    formats = [
        "%Y %b %d %I:%M:%S %p",  # 2024 Apr 29 05:21:10 PM
        "%Y-%m-%d %H:%M:%S%z",  # 2015-01-07 16:00:00-08:00
        "%Y-%m-%dT%H:%M:%S%z",  # ISO format
    ]

    for fmt in formats:
        try:
            dt = datetime.strptime(value.strip(), fmt)
            return dt.isoformat()
        except ValueError:
            continue

    return None


def parse_multilinestring_wkt(wkt: str | None) -> str | None:
    """
    Convert WKT MULTILINESTRING to PostGIS-compatible format.
    Input: 'MULTILINESTRING ((-122.473990553 37.781814028, -122.473914429 37.780764073))'
    Output: Same format (PostGIS can parse this directly)
    """
    if not wkt or not wkt.strip():
        return None

    wkt = wkt.strip()
    if not wkt.upper().startswith("MULTILINESTRING"):
        return None

    return wkt


def csv_row_to_record(row: dict[str, str]) -> dict[str, Any] | None:
    """Convert a CSV row into a database record."""
    # Skip rows without geometry
    line = parse_multilinestring_wkt(row.get("shape"))
    if not line:
        return None

    # Skip rows without objectid (required for upsert)
    source_objectid = parse_int(row.get("objectid"))
    if source_objectid is None:
        return None

    # Skip rows without regulation (NOT NULL constraint)
    regulation = normalize_regulation(row.get("REGULATION"))
    if not regulation:
        return None

    return {
        "source_objectid": source_objectid,
        "regulation": regulation,
        "days": row.get("DAYS") or None,
        "hrs_begin": parse_int(row.get("HRS_BEGIN")),
        "hrs_end": parse_int(row.get("HRS_END")),
        "hour_limit": parse_int(row.get("HRLIMIT")),
        "rpp_area1": row.get("RPPAREA1") or None,
        "rpp_area2": row.get("RPPAREA2") or None,
        "rpp_area3": row.get("RPPAREA3") or None,
        "reg_details": row.get("REGDETAILS") or None,
        "exceptions": row.get("EXCEPTIONS") or None,
        "from_time": row.get("FROM_TIME") or None,
        "to_time": row.get("TO_TIME") or None,
        "neighborhood": row.get("analysis_neighborhood") or None,
        "supervisor_district": row.get("supervisor_district") or None,
        "length_ft": parse_float(row.get("LENGTH_FT")),
        "line": line,
        "enacted": parse_date(row.get("ENACTED")),
        "data_as_of": parse_timestamp(row.get("data_as_of")),
    }


def chunked(iterable: list[Any], size: int) -> Iterable[list[Any]]:
    """Yield successive chunks from a list."""
    for i in range(0, len(iterable), size):
        yield iterable[i : i + size]


def load_csv(file_path: Path) -> list[dict[str, Any]]:
    """Load and parse CSV file into database records."""
    records = []
    skipped = 0

    with open(file_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            record = csv_row_to_record(row)
            if record:
                records.append(record)
            else:
                skipped += 1

    print(f"Loaded {len(records)} records from CSV (skipped {skipped} invalid rows)")
    return records


def find_csv_file() -> Path:
    """Find the parking regulations CSV file in the project root."""
    # __file__ is src/sweep_dreams/etl/parking_regulations_etl.py
    # Go up 4 levels: etl -> sweep_dreams -> src -> sweep-dreams (project root)
    project_root = Path(__file__).parent.parent.parent.parent

    # Look for files matching the pattern
    pattern = "Parking_regulations_*.csv"
    matches = list(project_root.glob(pattern))

    if not matches:
        raise FileNotFoundError(
            f"No parking regulations CSV found in {project_root}. "
            f"Expected file matching: {pattern}"
        )

    # Use the most recent file (by filename date)
    matches.sort(reverse=True)
    return matches[0]


def main():
    load_dotenv()

    # Find and load CSV
    csv_path = find_csv_file()
    print(f"Loading CSV: {csv_path}")
    records = load_csv(csv_path)

    if not records:
        print("No records to load")
        return

    # Connect to Supabase
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_KEY")

    if not url or not key:
        raise ValueError("SUPABASE_URL and SUPABASE_KEY must be set")

    supabase: Client = create_client(url, key)
    table = "parking_regulations"

    # Upsert in chunks
    batch_size = 500
    total_upserted = 0

    for batch in chunked(records, batch_size):
        _ = supabase.table(table).upsert(batch, on_conflict="source_objectid").execute()
        total_upserted += len(batch)
        print(f"Upserted {total_upserted}/{len(records)} records")

    print(f"Done! Loaded {total_upserted} parking regulations into {table}")


if __name__ == "__main__":
    main()
