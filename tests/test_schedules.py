from datetime import datetime
from zoneinfo import ZoneInfo

import pytest

from sweep_dreams.schedules import PACIFIC_TZ, SweepingSchedule, next_sweep_window


def assert_window(window: tuple[datetime, datetime], start: datetime, end: datetime) -> None:
    got_start, got_end = window
    assert got_start == start
    assert got_end == end


def test_holiday_and_unknown_weekday_raise(schedule_factory):
    holiday_schedule = schedule_factory(week_day="Holiday", weeks=(1,))
    with pytest.raises(ValueError, match="only on holidays"):
        next_sweep_window(holiday_schedule, now=datetime(2024, 1, 1, 9, tzinfo=PACIFIC_TZ))

    bad_label_schedule = schedule_factory(week_day="Funday", weeks=(1,))
    with pytest.raises(ValueError, match="Unknown weekday label"):
        next_sweep_window(bad_label_schedule, now=datetime(2024, 1, 1, 9, tzinfo=PACIFIC_TZ))


def test_missing_weeks_and_hours_raise(schedule_factory):
    no_weeks = schedule_factory(weeks=())
    with pytest.raises(ValueError, match="no active weeks"):
        next_sweep_window(no_weeks, now=datetime(2024, 1, 1, 9, tzinfo=PACIFIC_TZ))

    missing_hours: SweepingSchedule = schedule_factory()
    missing_hours.from_hour = None
    with pytest.raises(ValueError, match="missing from/to hours"):
        next_sweep_window(missing_hours, now=datetime(2024, 1, 1, 9, tzinfo=PACIFIC_TZ))


@pytest.mark.parametrize(
    "now,start,end",
    [
        (
            datetime(2024, 3, 6, 10, tzinfo=PACIFIC_TZ),  # before any March window
            datetime(2024, 3, 8, 12, tzinfo=PACIFIC_TZ),
            datetime(2024, 3, 8, 14, tzinfo=PACIFIC_TZ),
        ),
        (
            datetime(2024, 3, 8, 10, tzinfo=PACIFIC_TZ),  # before start on sweep day
            datetime(2024, 3, 8, 12, tzinfo=PACIFIC_TZ),
            datetime(2024, 3, 8, 14, tzinfo=PACIFIC_TZ),
        ),
        (
            datetime(2024, 3, 8, 12, 30, tzinfo=PACIFIC_TZ),  # during window
            datetime(2024, 3, 8, 12, tzinfo=PACIFIC_TZ),
            datetime(2024, 3, 8, 14, tzinfo=PACIFIC_TZ),
        ),
        (
            datetime(2024, 3, 8, 14, tzinfo=PACIFIC_TZ),  # exactly at end -> next occurrence
            datetime(2024, 3, 22, 12, tzinfo=PACIFIC_TZ),
            datetime(2024, 3, 22, 14, tzinfo=PACIFIC_TZ),
        ),
        (
            datetime(2024, 3, 8, 15, tzinfo=PACIFIC_TZ),  # after window
            datetime(2024, 3, 22, 12, tzinfo=PACIFIC_TZ),
            datetime(2024, 3, 22, 14, tzinfo=PACIFIC_TZ),
        ),
        (
            datetime(2024, 3, 23, 9, tzinfo=PACIFIC_TZ),  # after 4th Friday -> roll to next month
            datetime(2024, 4, 12, 12, tzinfo=PACIFIC_TZ),
            datetime(2024, 4, 12, 14, tzinfo=PACIFIC_TZ),
        ),
    ],
)
def test_multiweek_schedule_picks_next_window(schedule_factory, now, start, end):
    schedule = schedule_factory(week_day="Fri", weeks=(2, 4), from_hour=12, to_hour=14)
    assert_window(next_sweep_window(schedule, now=now), start, end)


def test_over_midnight_window_is_contiguous(schedule_factory):
    schedule = schedule_factory(week_day="Mon", weeks=(1,), from_hour=23, to_hour=1)
    now = datetime(2024, 4, 2, 0, 30, tzinfo=PACIFIC_TZ)  # During the overnight window that began Apr 1
    start = datetime(2024, 4, 1, 23, tzinfo=PACIFIC_TZ)
    end = datetime(2024, 4, 2, 1, tzinfo=PACIFIC_TZ)
    assert_window(next_sweep_window(schedule, now=now), start, end)


def test_occurrence_gap_skips_months_without_target_weekday(schedule_factory):
    schedule = schedule_factory(week_day="Sat", weeks=(5,), from_hour=9, to_hour=11)
    now = datetime(2025, 2, 1, 12, tzinfo=PACIFIC_TZ)  # February 2025 has only four Saturdays
    start = datetime(2025, 3, 29, 9, tzinfo=PACIFIC_TZ)  # First upcoming month with a 5th Saturday
    end = datetime(2025, 3, 29, 11, tzinfo=PACIFIC_TZ)
    assert_window(next_sweep_window(schedule, now=now), start, end)


def test_timezone_normalization(schedule_factory):
    schedule = schedule_factory(week_day="Fri", weeks=(2, 4), from_hour=12, to_hour=14)

    # Naive datetime should be treated as PACIFIC_TZ
    naive_now = datetime(2024, 3, 6, 10)
    start = datetime(2024, 3, 8, 12, tzinfo=PACIFIC_TZ)
    end = datetime(2024, 3, 8, 14, tzinfo=PACIFIC_TZ)
    assert_window(next_sweep_window(schedule, now=naive_now), start, end)

    # Aware datetime in another tz should be converted
    utc_now = datetime(2024, 3, 8, 20, 30, tzinfo=ZoneInfo("UTC"))  # 12:30pm Pacific
    assert_window(next_sweep_window(schedule, now=utc_now), start, end)
