import calendar
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from sweep_dreams.domain.models import (
    PACIFIC_TZ,
    ParkingRegulation,
    RecurringRule,
    BlockSchedule,
    SweepingSchedule,
    Weekday,
    _WEEKDAY_LOOKUP,
)


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
    active_weeks = (
        sorted(rule.pattern.weeks_of_month)
        if rule.pattern.weeks_of_month
        else [1, 2, 3, 4, 5]
    )
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
        raise ValueError(
            "Schedule applies only on holidays; next sweeping day is not defined."
        )
    if weekday_label not in _WEEKDAY_LOOKUP:
        raise ValueError(f"Unknown weekday label: {schedule.week_day!r}")
    weekday = _WEEKDAY_LOOKUP[weekday_label]

    active_weeks = [
        idx
        for idx, active in enumerate(
            [
                schedule.week1,
                schedule.week2,
                schedule.week3,
                schedule.week4,
                schedule.week5,
            ],
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


def earliest_sweep_window(
    block_schedule: BlockSchedule,
    *,
    now: datetime | None = None,
    tz: ZoneInfo | None = None,
) -> tuple[datetime, datetime]:
    """
    Compute the earliest sweep window across all rules in a BlockSchedule.

    Args:
        block_schedule: The block schedule with multiple rules
        now: Reference time (defaults to current time)
        tz: Timezone (defaults to PACIFIC_TZ)

    Returns:
        Tuple of (start, end) datetime for the earliest sweep window

    Raises:
        ValueError: If no valid sweep windows can be computed
    """
    earliest_start = None
    earliest_end = None

    for rule in block_schedule.rules:
        try:
            start, end = next_sweep_window_from_rule(rule=rule, now=now, tz=tz)
        except ValueError:
            # Skip rules that can't compute windows (e.g., holiday-only)
            continue

        if earliest_start is None or start < earliest_start:
            earliest_start = start
            earliest_end = end

    if earliest_start is None:
        raise ValueError(
            f"Could not compute sweep window for block {block_schedule.block}"
        )

    return earliest_start, earliest_end


def earliest_sweep_window_with_block_id(
    block_schedule: BlockSchedule,
    source_schedules: list[SweepingSchedule],
    *,
    now: datetime | None = None,
    tz: ZoneInfo | None = None,
) -> tuple[datetime, datetime, int]:
    """
    Compute the earliest sweep window and return its block_sweep_id.

    Args:
        block_schedule: The merged block schedule
        source_schedules: The underlying SweepingSchedule rows for this block
        now: Reference time (defaults to current time)
        tz: Timezone (defaults to PACIFIC_TZ)

    Returns:
        (start, end, block_sweep_id) for the earliest window

    Raises:
        ValueError: If no valid sweep window can be computed
    """
    tzinfo = tz or PACIFIC_TZ
    reference = _normalize_now(now, tzinfo)

    earliest_start: datetime | None = None
    earliest_end: datetime | None = None
    earliest_block_sweep_id: int | None = None

    for schedule in source_schedules:
        try:
            start, end = next_sweep_window(schedule, now=reference, tz=tzinfo)
        except ValueError:
            continue

        is_better_start = earliest_start is None or start < earliest_start
        is_same_start = earliest_start is not None and start == earliest_start
        if is_better_start or (
            is_same_start
            and earliest_block_sweep_id is not None
            and schedule.block_sweep_id < earliest_block_sweep_id
        ):
            earliest_start = start
            earliest_end = end
            earliest_block_sweep_id = schedule.block_sweep_id

    if (
        earliest_start is None
        or earliest_end is None
        or earliest_block_sweep_id is None
    ):
        raise ValueError(
            f"Could not compute sweep window for block {block_schedule.block}"
        )

    return earliest_start, earliest_end, earliest_block_sweep_id


# Mapping for parking regulation day ranges
_DAYS_TO_WEEKDAYS: dict[str, set[Weekday]] = {
    "m-f": {Weekday.MON, Weekday.TUE, Weekday.WED, Weekday.THU, Weekday.FRI},
    "m-sa": {Weekday.MON, Weekday.TUE, Weekday.WED, Weekday.THU, Weekday.FRI, Weekday.SAT},
    "m-su": {Weekday.MON, Weekday.TUE, Weekday.WED, Weekday.THU, Weekday.FRI, Weekday.SAT, Weekday.SUN},
    "sa-su": {Weekday.SAT, Weekday.SUN},
    "su": {Weekday.SUN},
    "sa": {Weekday.SAT},
}


def _parse_military_time(military: int) -> tuple[int, int]:
    """Parse military time (e.g., 800 -> (8, 0), 1800 -> (18, 0))."""
    hours = military // 100
    minutes = military % 100
    return hours, minutes


def next_parking_regulation_window(
    regulation: ParkingRegulation,
    *,
    now: datetime | None = None,
    tz: ZoneInfo | None = None,
) -> tuple[datetime, datetime]:
    """
    Compute the next time window when a parking regulation applies.

    For time-limited parking, this is when the restriction is active
    (e.g., 8am-6pm M-F means you can't park longer than the hour limit).

    Args:
        regulation: The parking regulation
        now: Reference time (defaults to current time)
        tz: Timezone (defaults to PACIFIC_TZ)

    Returns:
        Tuple of (start, end) datetime for the next regulation window

    Raises:
        ValueError: If regulation has no valid time/day configuration
    """
    tzinfo = tz or PACIFIC_TZ
    reference = _normalize_now(now, tzinfo)

    # Parse the days field
    days_str = (regulation.days or "").strip().lower()
    if not days_str or days_str not in _DAYS_TO_WEEKDAYS:
        raise ValueError(f"Unknown or missing days pattern: {regulation.days!r}")
    active_weekdays = _DAYS_TO_WEEKDAYS[days_str]

    # Parse time range
    if regulation.hrs_begin is None or regulation.hrs_end is None:
        raise ValueError("Regulation is missing hrs_begin/hrs_end")

    start_hour, start_min = _parse_military_time(regulation.hrs_begin)
    end_hour, end_min = _parse_military_time(regulation.hrs_end)

    # Search up to 8 days ahead (covers all weekdays)
    for day_offset in range(8):
        candidate_date = reference.date() + timedelta(days=day_offset)
        candidate_weekday = Weekday(candidate_date.weekday())

        if candidate_weekday not in active_weekdays:
            continue

        start_dt = datetime(
            candidate_date.year,
            candidate_date.month,
            candidate_date.day,
            start_hour,
            start_min,
            tzinfo=tzinfo,
        )
        end_dt = datetime(
            candidate_date.year,
            candidate_date.month,
            candidate_date.day,
            end_hour,
            end_min,
            tzinfo=tzinfo,
        )

        # Handle windows that cross midnight
        if end_dt <= start_dt:
            end_dt += timedelta(days=1)

        # Skip if window has already passed
        if end_dt <= reference:
            continue

        # Found a valid window
        return start_dt, end_dt

    raise ValueError("Unable to compute next regulation window within 8 days.")
