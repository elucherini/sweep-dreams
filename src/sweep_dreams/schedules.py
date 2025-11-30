from pydantic import BaseModel, Field, field_validator
from typing import Any
from datetime import datetime


Coord = tuple[float, float]

class SweepingSchedule(BaseModel):
    """
    A dataclass to model a complete sweeping schedule.
    """
    model_config = {"populate_by_name": True}
    cnn: int
    corridor: str
    limits: str
    cnn_right_left: str  # whether the schedule refers to the left or right side of the street
    block_side: str | None  # direction for the side of the street (east, west, southeast, etc)
    full_name: str  # schedule time in plaintext (e.g., Tue 1st, 3rd, 5th)
    week_day: str  # short for weekday
    from_hour: int  # 24-hour format
    to_hour: int  # 24-hour format
    week1: bool = Field(alias="week1")  # bools mapping schedule to the week
    week2: bool = Field(alias="week2")
    week3: bool = Field(alias="week3")
    week4: bool = Field(alias="week4")
    week5: bool = Field(alias="week5")
    holidays: bool
    block_sweep_id: int
    line: list[Coord]

    @field_validator("line", mode="before")
    def parse_linestring(cls, v: Any):
        if v is None:
            return []

        # The GeoJSON field arrives as a list of [lon, lat] pairs.
        if isinstance(v, list):
            return [tuple(map(float, coord[:2])) for coord in v if len(coord) >= 2]

        # Fallback for WKT-like strings (e.g., "LINESTRING (lon lat, lon lat)")
        if isinstance(v, str):
            text = v.strip()
            if text.upper().startswith("LINESTRING"):
                text = text[len("LINESTRING"):].strip()
            text = text.strip("()")
            coords: list[Coord] = []
            for pair in text.split(","):
                parts = pair.strip().split()
                if len(parts) != 2:
                    continue
                lon, lat = map(float, parts)
                coords.append((lon, lat))
            return coords

        return v


def parse_schedules(data: dict[str, Any]) -> list[SweepingSchedule]:
    """
    Parse the sweeping schedule GeoJSON into SweepingSchedule records.

    Args:
        data (dict[str, Any]): The GeoJSON payload to parse.
    """
    schedules: list[SweepingSchedule] = []
    for feature in data.get("features", []):
        properties = feature.get("properties", {})
        geometry = feature.get("geometry", {})
        if not geometry or not geometry.get("coordinates", None):
            # Skip rows with empty coordinates
            continue
        schedule = SweepingSchedule(
            cnn=properties.get("cnn"),
            corridor=properties.get("corridor", ""),
            limits=properties.get("limits", ""),
            cnn_right_left=properties.get("cnnrightleft", ""),
            block_side=properties.get("blockside", ""),
            full_name=properties.get("fullname", ""),
            weekday=properties.get("weekday", ""),
            from_hour=properties.get("fromhour"),
            to_hour=properties.get("tohour"),
            week1=properties.get("week1"),
            week2=properties.get("week2"),
            week3=properties.get("week3"),
            week4=properties.get("week4"),
            week5=properties.get("week5"),
            holidays=properties.get("holidays"),
            block_sweep_id=properties.get("blocksweepid"),
            line=geometry.get("coordinates", []),
        )
        schedules.append(schedule)

    return schedules
