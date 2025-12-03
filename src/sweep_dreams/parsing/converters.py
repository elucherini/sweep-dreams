"""Model conversion functions."""

from collections import defaultdict
from datetime import time
from typing import Any

from sweep_dreams.domain.models import (
    BlockKey,
    BlockSchedule,
    RecurringRule,
    SweepingSchedule,
    MonthlyPattern,
    TimeWindow,
    _WEEKDAY_LOOKUP,
)


def block_key_from_schedule(schedule: SweepingSchedule) -> BlockKey:
    """Build a BlockKey from a SweepingSchedule."""
    return BlockKey(
        cnn=schedule.cnn,
        corridor=schedule.corridor,
        limits=schedule.limits,
        cnn_right_left=schedule.cnn_right_left,
        block_side=schedule.block_side,
    )


def group_schedules_by_block(
    schedules: list[SweepingSchedule],
) -> dict[BlockKey, list[SweepingSchedule]]:
    """Group SweepingSchedule objects by their BlockKey."""
    grouped: dict[BlockKey, list[SweepingSchedule]] = defaultdict(list)
    for schedule in schedules:
        grouped[block_key_from_schedule(schedule)].append(schedule)
    return grouped


def sweeping_schedules_to_blocks(
    schedules: list[SweepingSchedule],
) -> list[BlockSchedule]:
    """
    Groups SweepingSchedule objects by block, merging rules.
    Validates geometry consistency within blocks.
    """
    # Group by BlockKey
    grouped: dict[BlockKey, list[SweepingSchedule]] = defaultdict(list)

    for schedule in schedules:
        grouped[block_key_from_schedule(schedule)].append(schedule)

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
                same_weeks = (
                    existing.pattern.weeks_of_month == rule.pattern.weeks_of_month
                )
                same_holidays = existing.skip_holidays == rule.skip_holidays

                if same_time and same_weeks and same_holidays:
                    existing.pattern.weekdays |= rule.pattern.weekdays
                    break
            else:
                merged_rules.append(rule)

        result.append(BlockSchedule(block=block, rules=merged_rules, line=geometry))

    return result
