import os
from typing import List
from supabase import create_client, Client
from utils import URL, fetch_data, lightly_parse_data, SFAddress
from dotenv import load_dotenv


TABLE_NAME = "sf_addresses"


if __name__ == "__main__":
    load_dotenv()

    data = fetch_data(URL)
    address_data: List[SFAddress] = lightly_parse_data(data)

    # Connect to db
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_KEY")
    supabase: Client = create_client(url, key)

    # Upsert for simplicity
    supabase.table(TABLE_NAME).upsert([
        address.__dict__ for address in address_data
    ]).execute()

    # Test queries
    test_zipcode = "94110"
    response = supabase.table(TABLE_NAME).select("eas_fullid", count="exact").eq("zip", test_zipcode).execute()
    print(f"# addresses in zipcode {test_zipcode}: {response.count}")
    response = (
        supabase.table(TABLE_NAME)
        .select("created_at")
        .order("created_at", desc=True)  # Sort by created_at in descending order
        .limit(1)  # Limit to the latest value
        .execute()
    )
    print(f"Latest created_at timestamp: {response.data[0]['created_at']}")