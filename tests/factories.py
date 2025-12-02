from collections.abc import Iterable
from typing import Any

from sweep_dreams.domain.models import SweepingSchedule


def make_schedule(
    *,
    week_day: str = "Fri",
    weeks: Iterable[int] = (2, 4),
    from_hour: int = 12,
    to_hour: int = 14,
    holidays: bool = False,
    overrides: dict[str, Any] | None = None,
) -> SweepingSchedule:
    """
    Lightweight factory to build SweepingSchedule objects for tests.

    Args:
        week_day: Weekday label such as "Mon" or "Friday".
        weeks: 1-based week numbers that should be active (e.g., (2, 4)).
        from_hour: Start hour (24-hour clock).
        to_hour: End hour (24-hour clock).
        holidays: Whether the schedule applies only on holidays.
        overrides: Optional dict to override any field on the model.
    """
    weeks_set = set(weeks)
    week_flags = {f"week{i}": i in weeks_set for i in range(1, 6)}
    base_data: dict[str, Any] = {
        "cnn": 1,
        "corridor": "Test Corridor",
        "limits": "Limits",
        "cnn_right_left": "R",
        "block_side": None,
        "full_name": "Synthetic schedule",
        "week_day": week_day,
        "from_hour": from_hour,
        "to_hour": to_hour,
        "holidays": holidays,
        "block_sweep_id": 999,
        "line": [(0.0, 0.0)],
        **week_flags,
    }
    if overrides:
        base_data.update(overrides)
    return SweepingSchedule(**base_data)
