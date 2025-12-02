"""Human-readable formatting functions for domain models."""

from sweep_dreams.domain.models import Weekday, RecurringRule, BlockSchedule


def rule_to_human(rule: RecurringRule) -> str:
    """
    Convert a RecurringRule to a human-readable string.

    Args:
        rule: The recurring rule to format

    Returns:
        Human-readable string like "Every 2nd, 4th Monday at 12pm-2pm"
    """
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


def schedule_to_human(schedule: BlockSchedule) -> list[str]:
    """
    Convert all rules in a BlockSchedule to human-readable strings.

    Args:
        schedule: The block schedule to format

    Returns:
        List of human-readable rule strings
    """
    return [rule_to_human(r) for r in schedule.rules]
