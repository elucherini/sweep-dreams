from datetime import time
from typing import Any
from zoneinfo import ZoneInfo
from enum import IntEnum

from pydantic import BaseModel, Field, field_validator


PACIFIC_TZ = ZoneInfo("America/Los_Angeles")

Coord = tuple[float, float]


class Weekday(IntEnum):
    MON = 0
    TUE = 1
    WED = 2
    THU = 3
    FRI = 4
    SAT = 5
    SUN = 6


_WEEKDAY_LOOKUP: dict[str, Weekday] = {
    # Dataset values observed: Mon, Tues, Wed, Thu, Fri, Sat, Sun, Holiday.
    "mon": Weekday.MON,
    "monday": Weekday.MON,
    "tues": Weekday.TUE,
    "tue": Weekday.TUE,
    "tuesday": Weekday.TUE,
    "wed": Weekday.WED,
    "weds": Weekday.WED,
    "wednesday": Weekday.WED,
    "thu": Weekday.THU,
    "thur": Weekday.THU,
    "thurs": Weekday.THU,
    "thursday": Weekday.THU,
    "fri": Weekday.FRI,
    "friday": Weekday.FRI,
    "sat": Weekday.SAT,
    "saturday": Weekday.SAT,
    "sun": Weekday.SUN,
    "sunday": Weekday.SUN,
}


class BlockKey(BaseModel):
    cnn: int
    corridor: str
    limits: str
    cnn_right_left: str
    block_side: str | None
    model_config = {"frozen": True}  # makes it hashable & usable as a dict key


class TimeWindow(BaseModel):
    start: time
    end: time


class MonthlyPattern(BaseModel):
    # e.g. {Weekday.MON, Weekday.FRI}
    weekdays: set[Weekday]

    # which weeks of the month (1–5); None => all
    weeks_of_month: set[int] | None = None


class RecurringRule(BaseModel):
    pattern: MonthlyPattern
    time_window: TimeWindow
    skip_holidays: bool = False


class BlockSchedule(BaseModel):
    block: BlockKey
    rules: list[RecurringRule]
    line: list[Coord]


class ParkingRegulation(BaseModel):
    """
    A dataclass to model a parking regulation (time-limited parking, etc.).
    """

    id: int
    regulation: str  # 'Time limited', 'No parking any time', etc.
    days: str | None = None  # 'M-F', 'M-Su', 'M-Sa'
    hrs_begin: int | None = None  # 900 = 9:00 AM (military-style)
    hrs_end: int | None = None  # 1800 = 6:00 PM
    hour_limit: int | None = None  # 2, 3, 4 hour limit
    rpp_area1: str | None = None  # Primary RPP area
    rpp_area2: str | None = None  # Secondary RPP area
    exceptions: str | None = None  # 'Yes. RPP holders are exempt...'
    from_time: str | None = None  # '9am' (human-readable)
    to_time: str | None = None  # '6pm' (human-readable)
    neighborhood: str | None = None  # 'Inner Richmond', 'Marina', etc.
    line: list[Coord] = []

    @field_validator("line", mode="before")
    def parse_multilinestring(cls, v: Any):
        if v is None:
            return []

        # Handle GeoJSON format
        if isinstance(v, dict) and "coordinates" in v:
            v = v.get("coordinates") or []
            # MultiLineString has nested arrays: [[[lon, lat], ...], ...]
            # Flatten to single list of coords (take first linestring)
            if v and isinstance(v[0], list) and isinstance(v[0][0], list):
                v = v[0]  # Take first linestring

        if isinstance(v, list):
            # Already a flat list of coords
            if v and isinstance(v[0], (tuple, list)) and isinstance(v[0][0], (int, float)):
                return [tuple(map(float, coord[:2])) for coord in v if len(coord) >= 2]
            return []

        return []


class SweepingSchedule(BaseModel):
    """
    A dataclass to model a complete sweeping schedule.
    """

    model_config = {"populate_by_name": True}
    cnn: int
    corridor: str
    limits: str
    cnn_right_left: (
        str  # whether the schedule refers to the left or right side of the street
    )
    block_side: (
        str | None
    )  # direction for the side of the street (east, west, southeast, etc)
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

        if isinstance(v, dict) and "coordinates" in v:
            v = v.get("coordinates") or []

        # The GeoJSON field arrives as a list of [lon, lat] pairs.
        if isinstance(v, list):
            return [tuple(map(float, coord[:2])) for coord in v if len(coord) >= 2]

        # Fallback for WKT-like strings (e.g., "LINESTRING (lon lat, lon lat)")
        if isinstance(v, str):
            text = v.strip()
            if text.upper().startswith("LINESTRING"):
                text = text[len("LINESTRING") :].strip()
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
