import type { RecurringRule, SweepingSchedule } from '../models';
import { Weekday } from '../models';

const PACIFIC_TZ = 'America/Los_Angeles';

/**
 * Format a Date as a clock time string in Pacific timezone.
 * Example: "2:30 PM"
 */
export function formatPacificClockTime(date: Date): string {
  return new Intl.DateTimeFormat('en-US', {
    timeZone: PACIFIC_TZ,
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  }).format(date);
}

const WEEKDAY_NAMES: Record<Weekday, string> = {
  [Weekday.MON]: 'Monday',
  [Weekday.TUE]: 'Tuesday',
  [Weekday.WED]: 'Wednesday',
  [Weekday.THU]: 'Thursday',
  [Weekday.FRI]: 'Friday',
  [Weekday.SAT]: 'Saturday',
  [Weekday.SUN]: 'Sunday',
};

const ORDINAL_NAMES: Record<number, string> = {
  1: '1st',
  2: '2nd',
  3: '3rd',
  4: '4th',
  5: '5th',
};

/**
 * Convert a RecurringRule to human-readable text.
 * Example: "Every 1st, 3rd Monday at 8am-10am"
 *
 * @param rule - The recurring rule to format
 * @returns Human-readable string
 */
export function formatRule(rule: RecurringRule): string {
  // Format weeks_of_month if it's a subset
  let weeksPrefix = '';
  const allWeeks = [1, 2, 3, 4, 5];
  const weeks = rule.pattern.weeks_of_month || allWeeks;

  // Only show week prefix if it's not all weeks
  const isAllWeeks = weeks.length === 5 && allWeeks.every(w => weeks.includes(w));

  if (!isAllWeeks) {
    const weeksSorted = [...weeks].sort((a, b) => a - b);
    if (weeksSorted.length === 1) {
      weeksPrefix = `${ORDINAL_NAMES[weeksSorted[0]]} `;
    } else {
      const weekNames = weeksSorted.map(w => ORDINAL_NAMES[w]);
      if (weekNames.length === 2) {
        weeksPrefix = `${weekNames[0]} and ${weekNames[1]} `;
      } else {
        const last = weekNames[weekNames.length - 1];
        const rest = weekNames.slice(0, -1);
        weeksPrefix = `${rest.join(', ')}, and ${last} `;
      }
    }
  }

  // Format weekdays
  const weekdaysSorted = [...rule.pattern.weekdays].sort((a, b) => a - b);
  const weekdayStr = weekdaysSorted.map(w => WEEKDAY_NAMES[w]).join(', ');

  // Convert military time to AM/PM format
  const formatHour = (hour: number): string => {
    if (hour === 0) return '12am';
    if (hour < 12) return `${hour}am`;
    if (hour === 12) return '12pm';
    return `${hour - 12}pm`;
  };

  const [startHour] = rule.time_window.start.split(':').map(Number);
  const [endHour] = rule.time_window.end.split(':').map(Number);
  const startStr = formatHour(startHour);
  const endStr = formatHour(endHour);

  return `Every ${weeksPrefix}${weekdayStr} at ${startStr}-${endStr}`;
}

/**
 * Convert a SweepingSchedule to human-readable text.
 * Uses the full_name field as fallback.
 *
 * @param schedule - The sweeping schedule
 * @returns Human-readable string
 */
export function formatSchedule(schedule: SweepingSchedule): string {
  // Supabase data already has full_name (e.g., "Mon 1st, 3rd, 5th 8am-10am")
  return schedule.full_name;
}
