from dataclasses import dataclass
from typing import Any, Dict, List
import requests
from datetime import datetime


URL = "https://data.sfgov.org/resource/ramy-di5m.geojson"


@dataclass
class SFAddress:
    """
    A dataclass to model a simple San Francisco address.
    """
    eas_fullid: str
    address: str
    zip: str
    latitude: float
    longitude: float
    created_at: str = datetime.now().isoformat()


def fetch_data(url: str) -> Dict[str, Any] | None:
    """Fetch JSON data from our API endpoint.
    
    Args:
        url (str): The URL of the API endpoint.
    """
    # Send a GET request
    response = requests.get(url)
    
    # Check if the response status code is 200 (OK)
    if response.status_code == 200:
        # Parse the JSON response
        data = response.json()
        return data
    else:
        print(f"Failed to fetch data. Status code: {response.status_code}")
        return None


def lightly_parse_data(data: Dict[str, Any]) -> List[SFAddress]:
    """
    Lightly parse JSON data to extract only the relevant fields.

    Args:
        data (list): The JSON data to parse.
    """
    # Let's parse the JSON data to extract the relevant fields
    addresses: List[SFAddress] = []
    for feature in data["features"]:
        properties = feature["properties"]
        geometry = feature["geometry"]
        address = SFAddress(
            eas_fullid=properties.get("eas_fullid", ""),
            address=properties.get("address", ""),
            zip=properties.get("zip_code", ""),
            latitude=geometry["coordinates"][1],
            longitude=geometry["coordinates"][0]
        )
        addresses.append(address)

    return addresses
