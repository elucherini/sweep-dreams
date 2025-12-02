import pandas as pd
from typing import Any
import json

from sweep_dreams.schedules import feature_to_dict


def json_to_pandas(json_data: dict[str, Any]) -> pd.DataFrame:
    """
    Parse the sweeping schedule GeoJSON into a pandas DataFrame.
    
    Args:
        json_data (dict[str, Any]): The GeoJSON payload to parse.
        
    Returns:
        pd.DataFrame: DataFrame with all fields from SweepingSchedule model.
    """
    records = []
    for feature in json_data.get("features", []):
        geometry = feature.get("geometry", {})
        if not geometry:
            continue
        
        # Skip rows with empty coordinates
        coordinates = geometry.get("coordinates", None)
        if not coordinates:
            continue
        
        record = feature_to_dict(feature)
        records.append(record)
    
    df = pd.DataFrame(records)

    # Convert hour columns to int (I know this is a repeat op but w/e)
    df['from_hour'] = df['from_hour'].astype(int)
    df['to_hour'] = df['to_hour'].astype(int)
    df['week1'] = df['week1'].astype(int)
    df['week2'] = df['week2'].astype(int)
    df['week3'] = df['week3'].astype(int)
    df['week4'] = df['week4'].astype(int)
    df['week5'] = df['week5'].astype(int)

    return df


def clean_schedules(json_data: dict[str, Any]):
    df = json_to_pandas(json_data)

    # Drop perfect duplicates apart from BlockSweepID, which is unique
    # Convert line to string temporarily for deduplication (lists are unhashable)
    df['line_str'] = df['line'].astype(str)
    columns_to_check = [col for col in df.columns if col not in ['BlockSweepID', 'line']]
    df = df.drop_duplicates(subset=columns_to_check, keep='first')
    df = df.drop(columns=['line_str'])

    return df

    # Merge overlapping schedules referring to the same 


if __name__ == "__main__":
    json_data = json.load(open("Street_Sweeping_Schedule_20251128.geojson", "r"))
    data = clean_schedules(json_data)