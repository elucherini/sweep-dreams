import calendar
from datetime import datetime, timedelta, time
from typing import Any
from zoneinfo import ZoneInfo
from enum import IntEnum
from collections import defaultdict

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
    model_config = {"frozen": True}   # makes it hashable & usable as a dict key


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

    @staticmethod
    def rule_to_human(rule: "RecurringRule") -> str:
        weekday_names = {
            Weekday.MON: "Monday",
            Weekday.TUE: "Tuesday",
            Weekday.WED: "Wednesday",
            Weekday.THU: "Thursday",
            Weekday.FRI: "Friday",
            Weekday.SAT: "Saturday",
            Weekday.SUN: "Sunday",
        }

        ordinal_names = {
            1: "1st",
            2: "2nd",
            3: "3rd",
            4: "4th",
            5: "5th",
        }

        # Format weeks_of_month if it's a subset
        weeks_prefix = ""
        if rule.pattern.weeks_of_month is not None and rule.pattern.weeks_of_month != {1, 2, 3, 4, 5}:
            weeks_sorted = sorted(rule.pattern.weeks_of_month)
            if len(weeks_sorted) == 1:
                weeks_prefix = f"{ordinal_names[weeks_sorted[0]]} "
            else:
                week_names = [ordinal_names[w] for w in weeks_sorted]
                if len(week_names) == 2:
                    weeks_prefix = f"{week_names[0]} and {week_names[1]} "
                else:
                    weeks_prefix = f"{', '.join(week_names[:-1])}, and {week_names[-1]} "

        weekdays_sorted = sorted(rule.pattern.weekdays)
        weekday_str = ", ".join(weekday_names[w] for w in weekdays_sorted)

        # Convert military time to AM/PM format
        def format_hour(hour: int) -> str:
            if hour == 0:
                return "12am"
            elif hour < 12:
                return f"{hour}am"
            elif hour == 12:
                return "12pm"
            else:
                return f"{hour - 12}pm"

        t = rule.time_window
        start_str = format_hour(t.start.hour)
        end_str = format_hour(t.end.hour)

        return f"Every {weeks_prefix}{weekday_str} at {start_str}-{end_str}"


class BlockSchedule(BaseModel):
    block: BlockKey
    rules: list[RecurringRule]
    line: list[Coord]

    @staticmethod
    def schedule_to_human(schedule: "BlockSchedule") -> str:
        return [RecurringRule.rule_to_human(r) for r in schedule.rules]


def parse_block_schedule(raw: dict[str, Any]) -> tuple[BlockKey, RecurringRule]:
    sched = raw["schedule"]

    block = BlockKey(
        cnn=sched["cnn"],
        corridor=sched["corridor"],
        limits=sched["limits"],
        cnn_right_left=sched["cnn_right_left"],
        block_side=sched["block_side"],
    )

    weekday = _WEEKDAY_LOOKUP[sched["week_day"]]

    weeks = {
        i for i in range(1, 6)
        if sched.get(f"week{i}", False)
    } or None

    rule = RecurringRule(
        pattern=MonthlyPattern(
            weekdays={weekday},
            weeks_of_month=weeks,
        ),
        time_window=TimeWindow(
            start=time(sched["from_hour"]),
            end=time(sched["to_hour"]),
        ),
        skip_holidays=bool(sched.get("holidays", False)),
    )

    return block, rule


def merge_block_schedules(raw_entries: list[dict]) -> list[BlockSchedule]:
    # group by BlockKey
    grouped: dict[BlockKey, list[RecurringRule]] = defaultdict(list)

    for raw in raw_entries:
        block, rule = parse_block_schedule(raw)
        grouped[block].append(rule)

    merged: list[BlockSchedule] = []

    for block, rules in grouped.items():
        # merge rules with same pattern except weekday
        merged_rules: list[RecurringRule] = []

        for rule in rules:
            # try to merge into an existing rule
            for existing in merged_rules:
                same_time = existing.time_window == rule.time_window
                same_weeks = existing.pattern.weeks_of_month == rule.pattern.weeks_of_month
                same_holidays = existing.skip_holidays == rule.skip_holidays
                same_bounds = (
                    existing.start_date == rule.start_date
                    and existing.end_date == rule.end_date
                )

                if same_time and same_weeks and same_holidays and same_bounds:
                    existing.pattern.weekdays |= rule.pattern.weekdays
                    break
            else:
                merged_rules.append(rule)

        merged.append(BlockSchedule(block=block, rules=merged_rules))

    return merged


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


def sweeping_schedules_to_blocks(
    schedules: list[SweepingSchedule]
) -> list[BlockSchedule]:
    """
    Groups SweepingSchedule objects by block, merging rules.
    Validates geometry consistency within blocks.
    """
    # Group by BlockKey
    grouped: dict[BlockKey, list[SweepingSchedule]] = defaultdict(list)

    for schedule in schedules:
        block = BlockKey(
            cnn=schedule.cnn,
            corridor=schedule.corridor,
            limits=schedule.limits,
            cnn_right_left=schedule.cnn_right_left,
            block_side=schedule.block_side,
        )
        grouped[block].append(schedule)

    result: list[BlockSchedule] = []
    for block, block_schedules in grouped.items():
        # Extract geometry from first schedule
        geometry = block_schedules[0].line

        # Validate all geometries match
        for sched in block_schedules[1:]:
            if sched.line != geometry:
                raise ValueError(
                    f"Inconsistent geometries for block {block}: "
                    f"expected {geometry}, got {sched.line}"
                )

        # Convert each SweepingSchedule to RecurringRule
        rules: list[RecurringRule] = []
        for sched in block_schedules:
            weekday = _WEEKDAY_LOOKUP[sched.week_day.lower()]
            weeks = {i for i in range(1, 6) if getattr(sched, f"week{i}")} or None

            rule = RecurringRule(
                pattern=MonthlyPattern(
                    weekdays={weekday},
                    weeks_of_month=weeks,
                ),
                time_window=TimeWindow(
                    start=time(sched.from_hour),
                    end=time(sched.to_hour),
                ),
                skip_holidays=sched.holidays,
            )
            rules.append(rule)

        # Merge rules with identical patterns (optional optimization)
        merged_rules: list[RecurringRule] = []
        for rule in rules:
            # Try to merge into an existing rule
            for existing in merged_rules:
                same_time = existing.time_window == rule.time_window
                same_weeks = existing.pattern.weeks_of_month == rule.pattern.weeks_of_month
                same_holidays = existing.skip_holidays == rule.skip_holidays

                if same_time and same_weeks and same_holidays:
                    existing.pattern.weekdays |= rule.pattern.weekdays
                    break
            else:
                merged_rules.append(rule)

        result.append(BlockSchedule(block=block, rules=merged_rules, line=geometry))

    return result


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


def next_sweep_window_from_rule(
    rule: RecurringRule,
    *,
    now: datetime | None = None,
    tz: ZoneInfo | None = None,
) -> tuple[datetime, datetime]:
    """
    Compute the next sweeping window (start, end) for a RecurringRule.

    Core scheduling logic extracted for reuse with BlockSchedule.
    """
    tzinfo = tz or PACIFIC_TZ
    reference = _normalize_now(now, tzinfo)

    # Extract weekday from pattern (should only have one)
    if not rule.pattern.weekdays:
        raise ValueError("Rule has no weekdays configured.")
    weekday = next(iter(rule.pattern.weekdays))

    # Get active weeks (None means all weeks 1-5)
    active_weeks = sorted(rule.pattern.weeks_of_month) if rule.pattern.weeks_of_month else [1, 2, 3, 4, 5]
    if not active_weeks:
        raise ValueError("Rule has no active weeks configured.")

    start_hour = rule.time_window.start.hour
    end_hour = rule.time_window.end.hour

    for month_offset in range(0, 13):
        month_index = reference.month - 1 + month_offset
        year = reference.year + month_index // 12
        month = (month_index % 12) + 1

        for occurrence in active_weeks:
            day = _nth_weekday(year, month, weekday, occurrence)
            if day is None:
                continue

            start_dt = datetime(year, month, day, start_hour, tzinfo=tzinfo)
            end_dt = datetime(year, month, day, end_hour, tzinfo=tzinfo)
            if end_dt <= start_dt:
                end_dt += timedelta(days=1)  # Handle windows that cross midnight.

            if end_dt <= reference:
                continue  # Window already passed.

            if start_dt <= reference <= end_dt or start_dt > reference:
                return start_dt, end_dt

    raise ValueError("Unable to compute next sweep window within 12 months.")


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
