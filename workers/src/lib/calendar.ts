import type { RecurringRule, SweepingSchedule } from '../models';
import { WEEKDAY_LOOKUP, Weekday } from '../models';

const PACIFIC_TZ = 'America/Los_Angeles';

/**
 * Find the day of the month for the nth occurrence of a weekday.
 * Example: nthWeekday(2025, 1, Weekday.MON, 2) returns the 2nd Monday in Jan 2025
 *
 * @param year - The year
 * @param month - The month (1-12)
 * @param weekday - The weekday enum value (0=Monday, 6=Sunday)
 * @param occurrence - Which occurrence (1-5)
 * @returns Day of month, or null if it doesn't exist
 */
function nthWeekday(year: number, month: number, weekday: Weekday, occurrence: number): number | null {
  // Get the first day of the month
  const firstDay = new Date(year, month - 1, 1);
  const firstWeekday = firstDay.getDay();  // 0 = Sunday in JavaScript

  // Convert JavaScript weekday (0=Sunday) to our enum (0=Monday)
  // JavaScript: Sun=0, Mon=1, Tue=2, ..., Sat=6
  // Our enum:   Mon=0, Tue=1, Wed=2, ..., Sun=6
  // Formula: (jsWeekday + 6) % 7 = ourWeekday
  const adjustedFirstWeekday = (firstWeekday + 6) % 7;

  // Calculate the day for the nth occurrence
  let day = 1 + ((weekday - adjustedFirstWeekday + 7) % 7) + 7 * (occurrence - 1);

  // Check if this day exists in the month
  const daysInMonth = new Date(year, month, 0).getDate();
  return day <= daysInMonth ? day : null;
}

/**
 * Compute the next sweep window (start, end) for a RecurringRule.
 * Port of Python's next_sweep_window_from_rule().
 *
 * @param rule - The recurring rule
 * @param now - Reference time (defaults to current time)
 * @returns Tuple of [start, end] datetimes
 */
export function nextSweepWindowFromRule(
  rule: RecurringRule,
  now?: Date,
): [Date, Date] {
  const reference = now || new Date();

  // Extract weekday from pattern (should only have one)
  if (rule.pattern.weekdays.length === 0) {
    throw new Error('Rule has no weekdays configured.');
  }
  const weekday = rule.pattern.weekdays[0];

  // Get active weeks (null means all weeks 1-5)
  const activeWeeks = rule.pattern.weeks_of_month
    ? [...rule.pattern.weeks_of_month].sort((a, b) => a - b)
    : [1, 2, 3, 4, 5];

  if (activeWeeks.length === 0) {
    throw new Error('Rule has no active weeks configured.');
  }

  const [startHour, startMin] = rule.time_window.start.split(':').map(Number);
  const [endHour, endMin] = rule.time_window.end.split(':').map(Number);

  // Search up to 13 months ahead
  for (let monthOffset = 0; monthOffset < 13; monthOffset++) {
    const monthIndex = reference.getMonth() + monthOffset;
    const year = reference.getFullYear() + Math.floor(monthIndex / 12);
    const month = (monthIndex % 12) + 1;

    for (const occurrence of activeWeeks) {
      const day = nthWeekday(year, month, weekday, occurrence);
      if (day === null) continue;

      // Create start/end datetimes
      // Note: JavaScript Date constructor uses 0-indexed months
      let startDt = new Date(year, month - 1, day, startHour, startMin || 0);
      let endDt = new Date(year, month - 1, day, endHour, endMin || 0);

      // Handle windows that cross midnight
      if (endDt <= startDt) {
        endDt = new Date(endDt.getTime() + 24 * 60 * 60 * 1000);
      }

      // Skip windows that already passed
      if (endDt <= reference) continue;

      // Return the first valid window (in progress or future)
      if (startDt <= reference || startDt > reference) {
        return [startDt, endDt];
      }
    }
  }

  throw new Error('Unable to compute next sweep window within 12 months.');
}

/**
 * Compute the next sweep window for a raw SweepingSchedule.
 * Port of Python's next_sweep_window().
 *
 * @param schedule - The sweeping schedule
 * @param now - Reference time (defaults to current time)
 * @returns Tuple of [start, end] datetimes
 */
export function nextSweepWindow(
  schedule: SweepingSchedule,
  now?: Date,
): [Date, Date] {
  const reference = now || new Date();

  const weekdayLabel = (schedule.week_day || '').trim().toLowerCase();
  if (weekdayLabel === 'holiday') {
    throw new Error('Schedule applies only on holidays; next sweeping day is not defined.');
  }

  const weekday = WEEKDAY_LOOKUP[weekdayLabel];
  if (weekday === undefined) {
    throw new Error(`Unknown weekday label: ${schedule.week_day}`);
  }

  // Extract active weeks from boolean flags
  const activeWeeks: number[] = [];
  if (schedule.week1) activeWeeks.push(1);
  if (schedule.week2) activeWeeks.push(2);
  if (schedule.week3) activeWeeks.push(3);
  if (schedule.week4) activeWeeks.push(4);
  if (schedule.week5) activeWeeks.push(5);

  if (activeWeeks.length === 0) {
    throw new Error('Schedule has no active weeks configured.');
  }

  // Search up to 13 months ahead
  for (let monthOffset = 0; monthOffset < 13; monthOffset++) {
    const monthIndex = reference.getMonth() + monthOffset;
    const year = reference.getFullYear() + Math.floor(monthIndex / 12);
    const month = (monthIndex % 12) + 1;

    for (const occurrence of activeWeeks.sort((a, b) => a - b)) {
      const day = nthWeekday(year, month, weekday, occurrence);
      if (day === null) continue;

      let startDt = new Date(year, month - 1, day, schedule.from_hour, 0);
      let endDt = new Date(year, month - 1, day, schedule.to_hour, 0);

      // Handle windows that cross midnight
      if (endDt <= startDt) {
        endDt = new Date(endDt.getTime() + 24 * 60 * 60 * 1000);
      }

      // Skip windows that already passed
      if (endDt <= reference) continue;

      if (startDt <= reference || startDt > reference) {
        return [startDt, endDt];
      }
    }
  }

  throw new Error('Unable to compute next sweep window within 12 months.');
}

/**
 * Format datetime to Pacific timezone ISO8601 string.
 * Example: "2025-01-15T08:00:00-08:00"
 */
export function formatPacificTime(date: Date): string {
  // Get the date parts in Pacific timezone
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: PACIFIC_TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
    timeZoneName: 'short',
  });

  const parts = formatter.formatToParts(date);
  const getValue = (type: string) => parts.find(p => p.type === type)?.value || '';

  const year = getValue('year');
  const month = getValue('month');
  const day = getValue('day');
  const hour = getValue('hour');
  const minute = getValue('minute');
  const second = getValue('second');
  const timeZoneName = getValue('timeZoneName');

  // Determine offset from timezone name (PST = -08:00, PDT = -07:00)
  const offset = timeZoneName.includes('PDT') ? '-07:00' : '-08:00';

  return `${year}-${month}-${day}T${hour}:${minute}:${second}${offset}`;
}
