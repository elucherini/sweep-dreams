import os
from supabase import create_client, Client
from dotenv import load_dotenv
import requests
from typing import Any
from sweep_dreams.schedules import SweepingSchedule, parse_schedules


URL = "https://data.sfgov.org/resource/yhqp-riqs.geojson"


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
    all_features = []
    offset = 0
    page = 1
    
    while True:
        # Add pagination parameters to URL
        params = {
            "$limit": LIMIT_PER_PAGE,
            "$offset": offset
        }
        
        # Send a GET request with pagination parameters
        response = requests.get(url, params=params)
        
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
        print(f"Fetched page {page}: {len(features)} features (total: {len(all_features)})")
        
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
    
    # Construct combined GeoJSON FeatureCollection
    if not all_features:
        print("No features found")
        return None
    
    combined_data = {
        "type": "FeatureCollection",
        "features": all_features
    }
    
    print(f"Total features fetched: {len(all_features)}")
    return combined_data


if __name__ == "__main__":
    load_dotenv()

    data = fetch_data(URL)
    address_data: list[SweepingSchedule] = parse_schedules(data)

    # Connect to db
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_KEY")
    table = os.environ.get("SUPABASE_TABLE")
    supabase: Client = create_client(url, key)

    # Upsert for simplicity
    supabase.table(table).upsert([
        address.model_dump(by_alias=True) for address in address_data
    ]).execute()
