import calendar
from datetime import datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

from pydantic import BaseModel, Field, field_validator


PACIFIC_TZ = ZoneInfo("America/Los_Angeles")
Coord = tuple[float, float]
_WEEKDAY_LOOKUP = {
    # Dataset values observed: Mon, Tues, Wed, Thu, Fri, Sat, Sun, Holiday.
    "mon": 0,
    "monday": 0,
    "tues": 1,
    "tue": 1,
    "tuesday": 1,
    "wed": 2,
    "weds": 2,
    "wednesday": 2,
    "thu": 3,
    "thur": 3,
    "thurs": 3,
    "thursday": 3,
    "fri": 4,
    "friday": 4,
    "sat": 5,
    "saturday": 5,
    "sun": 6,
    "sunday": 6,
}


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

        if isinstance(v, dict) and "coordinates" in v:
            v = v.get("coordinates") or []

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
            week_day=properties.get("weekday", ""),
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


def _nth_weekday(year: int, month: int, weekday: int, occurrence: int) -> int | None:
    """Return the day of the month for the nth occurrence of a weekday."""
    first_weekday, days_in_month = calendar.monthrange(year, month)
    day = 1 + ((weekday - first_weekday) % 7) + 7 * (occurrence - 1)
    return day if day <= days_in_month else None


def _normalize_now(now: datetime | None, tz: ZoneInfo) -> datetime:
    if now is None:
        return datetime.now(tz)
    if now.tzinfo is None:
        return now.replace(tzinfo=tz)
    return now.astimezone(tz)


def next_sweep_window(
    schedule: SweepingSchedule,
    *,
    now: datetime | None = None,
    tz: ZoneInfo | None = None,
) -> tuple[datetime, datetime]:
    """
    Compute the next sweeping window (start, end) for a schedule.
    """
    tzinfo = tz or PACIFIC_TZ
    reference = _normalize_now(now, tzinfo)

    weekday_label = (schedule.week_day or "").strip().lower()
    if weekday_label == "holiday":
        raise ValueError("Schedule applies only on holidays; next sweeping day is not defined.")
    if weekday_label not in _WEEKDAY_LOOKUP:
        raise ValueError(f"Unknown weekday label: {schedule.week_day!r}")
    weekday = _WEEKDAY_LOOKUP[weekday_label]

    active_weeks = [
        idx
        for idx, active in enumerate(
            [schedule.week1, schedule.week2, schedule.week3, schedule.week4, schedule.week5],
            start=1,
        )
        if bool(active)
    ]
    if not active_weeks:
        raise ValueError("Schedule has no active weeks configured.")
    if schedule.from_hour is None or schedule.to_hour is None:
        raise ValueError("Schedule is missing from/to hours.")

    for month_offset in range(0, 13):
        month_index = reference.month - 1 + month_offset
        year = reference.year + month_index // 12
        month = (month_index % 12) + 1

        for occurrence in sorted(active_weeks):
            day = _nth_weekday(year, month, weekday, occurrence)
            if day is None:
                continue

            start_dt = datetime(year, month, day, schedule.from_hour, tzinfo=tzinfo)
            end_dt = datetime(year, month, day, schedule.to_hour, tzinfo=tzinfo)
            if end_dt <= start_dt:
                end_dt += timedelta(days=1)  # Handle windows that cross midnight.

            if end_dt <= reference:
                continue  # Window already passed.

            if start_dt <= reference <= end_dt or start_dt > reference:
                return start_dt, end_dt

    raise ValueError("Unable to compute next sweep window within 12 months.")
