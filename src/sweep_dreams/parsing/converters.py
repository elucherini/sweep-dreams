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


def parse_block_schedule(raw: dict[str, Any]) -> tuple[BlockKey, RecurringRule]:
    """Parse a raw block schedule dict into BlockKey and RecurringRule."""
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
    """Merge raw block schedules by BlockKey and combine rules."""
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
                # Note: start_date and end_date attributes don't exist on RecurringRule
                # This logic was in the original but appears to be dead code

                if same_time and same_weeks and same_holidays:
                    existing.pattern.weekdays |= rule.pattern.weekdays
                    break
            else:
                merged_rules.append(rule)

        merged.append(BlockSchedule(block=block, rules=merged_rules, line=[]))

    return merged


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
