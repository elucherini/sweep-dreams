"""GeoJSON parsing functions."""

from typing import Any

from sweep_dreams.domain.models import SweepingSchedule


def feature_to_dict(feature: dict[str, Any]) -> dict[str, Any]:
    """
    Extract a clean dictionary from a GeoJSON feature.

    Args:
        feature (dict[str, Any]): A GeoJSON feature with properties and geometry.

    Returns:
        dict[str, Any]: Dictionary with all SweepingSchedule fields.
    """
    properties = feature.get("properties", {})
    geometry = feature.get("geometry", {})
    coordinates = geometry.get("coordinates", [])

    return {
        "cnn": properties.get("cnn"),
        "corridor": properties.get("corridor", ""),
        "limits": properties.get("limits", ""),
        "cnn_right_left": properties.get("cnnrightleft", ""),
        "block_side": properties.get("blockside", ""),
        "full_name": properties.get("fullname", ""),
        "week_day": properties.get("weekday", ""),
        "from_hour": properties.get("fromhour"),
        "to_hour": properties.get("tohour"),
        "week1": properties.get("week1"),
        "week2": properties.get("week2"),
        "week3": properties.get("week3"),
        "week4": properties.get("week4"),
        "week5": properties.get("week5"),
        "holidays": properties.get("holidays"),
        "block_sweep_id": properties.get("blocksweepid"),
        "line": coordinates,
    }


def parse_schedules(data: dict[str, Any]) -> list[SweepingSchedule]:
    """
    Parse the sweeping schedule GeoJSON into SweepingSchedule records.

    Args:
        data (dict[str, Any]): The GeoJSON payload to parse.
    """
    schedules: list[SweepingSchedule] = []
    for feature in data.get("features", []):
        geometry = feature.get("geometry", {})
        if not geometry or not geometry.get("coordinates", None):
            # Skip rows with empty coordinates
            continue

        record = feature_to_dict(feature)
        schedule = SweepingSchedule(**record)
        schedules.append(schedule)

    return schedules
