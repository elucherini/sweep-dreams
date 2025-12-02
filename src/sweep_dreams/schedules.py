"""
Backward compatibility layer for schedules module.
This module re-exports from the new domain and parsing structure.
"""

# Re-export all domain models
from sweep_dreams.domain.models import (
    PACIFIC_TZ,
    Coord,
    Weekday,
    _WEEKDAY_LOOKUP,
    BlockKey,
    TimeWindow,
    MonthlyPattern,
    RecurringRule,
    BlockSchedule,
    SweepingSchedule,
)

# Re-export calendar functions
from sweep_dreams.domain.calendar import (
    _nth_weekday,
    _normalize_now,
    next_sweep_window_from_rule,
    next_sweep_window,
    earliest_sweep_window,
)

# Re-export parsing functions
from sweep_dreams.parsing.geojson import (
    feature_to_dict,
    parse_schedules,
)

from sweep_dreams.parsing.converters import (
    parse_block_schedule,
    merge_block_schedules,
    sweeping_schedules_to_blocks,
)

# Import formatting functions for compatibility shims
from sweep_dreams.domain import formatting

# Re-add static methods for backward compatibility
# These will be removed in Phase 5
RecurringRule.rule_to_human = staticmethod(formatting.rule_to_human)
BlockSchedule.schedule_to_human = staticmethod(formatting.schedule_to_human)
