import os
import time
from typing import Any, Iterable

import requests
from dotenv import load_dotenv
from requests.adapters import HTTPAdapter
from supabase import Client, create_client
from urllib3.util import Retry

from sweep_dreams.domain.models import SweepingSchedule
from sweep_dreams.parsing.geojson import parse_schedules


URL = "https://data.sfgov.org/resource/yhqp-riqs.geojson"


def get_session() -> requests.Session:
    """Create a requests session with retries/backoff for transient failures."""
    retries = Retry(
        total=5,
        backoff_factor=0.5,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["GET"],
        raise_on_status=False,
    )
    adapter = HTTPAdapter(max_retries=retries)
    session = requests.Session()
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    return session


def fetch_data(url: str, page_limit: int | None = None) -> dict[str, Any] | None:
    """Fetch JSON data from our API endpoint with pagination support.

    Args:
        url (str): The URL of the API endpoint.
        page_limit (int | None): Optional limit on number of pages to fetch for debugging.
                                 If None, fetches all available pages.

    Returns:
        dict[str, Any] | None: Combined GeoJSON FeatureCollection with all features,
                               or None if the request failed.
    """
    LIMIT_PER_PAGE = 1000
    READ_TIMEOUT = 20  # seconds
    CONNECT_TIMEOUT = 5

    session = get_session()
    all_features = []
    offset = 0
    page = 1

    while True:
        # Add pagination parameters to URL
        # $order ensures stable pagination (without it, records can appear on multiple pages)
        params = {"$limit": LIMIT_PER_PAGE, "$offset": offset, "$order": "blocksweepid"}

        try:
            response = session.get(
                url,
                params=params,
                timeout=(CONNECT_TIMEOUT, READ_TIMEOUT),
            )
        except requests.exceptions.RequestException as exc:
            print(f"Request failed on page {page} (offset {offset}): {exc}")
            return None

        # Check if the response status code is 200 (OK)
        if response.status_code != 200:
            print(f"Failed to fetch data. Status code: {response.status_code}")
            return None

        # Parse the JSON response
        data = response.json()

        # Extract features from GeoJSON FeatureCollection
        features = data.get("features", [])
        if not features:
            # No more features, we're done
            break

        all_features.extend(features)
        print(
            f"Fetched page {page}: {len(features)} features (total: {len(all_features)})"
        )

        # If we got fewer features than the limit, we've reached the end
        if len(features) < LIMIT_PER_PAGE:
            break

        # Check page limit for debugging
        if page_limit is not None and page >= page_limit:
            print(f"Reached page limit ({page_limit}), stopping pagination")
            break

        # Move to next page
        offset += LIMIT_PER_PAGE
        page += 1
        time.sleep(0.2)  # small delay to avoid hammering the API

    # Construct combined GeoJSON FeatureCollection
    if not all_features:
        print("No features found")
        return None

    combined_data = {"type": "FeatureCollection", "features": all_features}

    print(f"Total features fetched: {len(all_features)}")
    return combined_data


def chunked(iterable: list[Any], size: int) -> Iterable[list[Any]]:
    """Yield successive chunks from a list."""
    for i in range(0, len(iterable), size):
        yield iterable[i : i + size]


def schedule_to_record(schedule: SweepingSchedule) -> dict[str, Any]:
    """Convert a SweepingSchedule into a payload the Supabase API expects."""
    record = schedule.model_dump(by_alias=True)
    coords = record.get("line") or []
    if coords:
        record["line"] = {"type": "LineString", "coordinates": coords}
    else:
        record["line"] = None
    return record


if __name__ == "__main__":
    load_dotenv()

    data = fetch_data(URL)
    address_data: list[SweepingSchedule] = parse_schedules(data)

    # Connect to db
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_KEY")
    table = os.environ.get("SUPABASE_TABLE")
    supabase: Client = create_client(url, key)

    # Upsert in chunks to keep payload sizes reasonable for ~37k rows
    for batch in chunked(
        [schedule_to_record(address) for address in address_data], 1000
    ):
        supabase.table(table).upsert(batch).execute()
