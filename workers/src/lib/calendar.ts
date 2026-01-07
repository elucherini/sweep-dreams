import type { RecurringRule, SweepingSchedule } from '../models';
import { WEEKDAY_LOOKUP, Weekday } from '../models';

const PACIFIC_TZ = 'America/Los_Angeles';

/**
 * Parse a days string like "M-F", "M-Sa", "M-Su" into a set of weekdays.
 * Case-insensitive.
 *
 * @param days - Days string (e.g., "M-F", "M-Sa", "M-Su")
 * @returns Set of Weekday enum values
 */
export function parseDaysString(days: string): Set<Weekday> {
  const normalized = days.trim().toLowerCase();

  // Handle common patterns
  if (normalized === 'm-f') {
    return new Set([Weekday.MON, Weekday.TUE, Weekday.WED, Weekday.THU, Weekday.FRI]);
  }
  if (normalized === 'm-sa') {
    return new Set([Weekday.MON, Weekday.TUE, Weekday.WED, Weekday.THU, Weekday.FRI, Weekday.SAT]);
  }
  if (normalized === 'm-su') {
    return new Set([Weekday.MON, Weekday.TUE, Weekday.WED, Weekday.THU, Weekday.FRI, Weekday.SAT, Weekday.SUN]);
  }

  throw new Error(`Unknown days pattern: ${days}`);
}

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

/**
 * Convert military time (e.g., 900 = 9:00 AM, 1800 = 6:00 PM) to hours and minutes.
 *
 * @param militaryTime - Time in military format (e.g., 900, 1800)
 * @returns Tuple of [hours, minutes]
 */
function parseMilitaryTime(militaryTime: number): [number, number] {
  const hours = Math.floor(militaryTime / 100);
  const minutes = militaryTime % 100;
  return [hours, minutes];
}

/**
 * Get the JavaScript weekday (0=Sunday) from a Date in Pacific time.
 *
 * @param date - The date to check
 * @returns JavaScript weekday (0=Sunday, 6=Saturday)
 */
function getPacificWeekday(date: Date): number {
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: PACIFIC_TZ,
    weekday: 'short',
  });
  const weekdayStr = formatter.format(date).toLowerCase();

  const jsWeekdayMap: Record<string, number> = {
    'sun': 0,
    'mon': 1,
    'tue': 2,
    'wed': 3,
    'thu': 4,
    'fri': 5,
    'sat': 6,
  };
  return jsWeekdayMap[weekdayStr] ?? 0;
}

/**
 * Get date parts (year, month, day, hour, minute) in Pacific timezone.
 *
 * @param date - The date to extract parts from
 * @returns Object with year, month (1-12), day, hour, minute
 */
function getPacificDateParts(date: Date): { year: number; month: number; day: number; hour: number; minute: number } {
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: PACIFIC_TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });

  const parts = formatter.formatToParts(date);
  const getValue = (type: string) => parseInt(parts.find(p => p.type === type)?.value || '0', 10);

  return {
    year: getValue('year'),
    month: getValue('month'),
    day: getValue('day'),
    hour: getValue('hour'),
    minute: getValue('minute'),
  };
}

/**
 * Create a Date in Pacific timezone from date parts.
 *
 * @param year - Year
 * @param month - Month (1-12)
 * @param day - Day of month
 * @param hour - Hour (0-23)
 * @param minute - Minute (0-59)
 * @returns Date object
 */
function createPacificDate(year: number, month: number, day: number, hour: number, minute: number): Date {
  // Create a date string in ISO format with Pacific offset
  // We'll use a temporary date to determine if it's PST or PDT
  const tempDate = new Date(year, month - 1, day);
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: PACIFIC_TZ,
    timeZoneName: 'short',
  });
  const parts = formatter.formatToParts(tempDate);
  const tzName = parts.find(p => p.type === 'timeZoneName')?.value || 'PST';
  const offset = tzName.includes('PDT') ? '-07:00' : '-08:00';

  const isoString = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}T${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}:00${offset}`;
  return new Date(isoString);
}

/**
 * Calculate the next move deadline for a time-limited parking regulation.
 *
 * Logic:
 * - If currently within a regulation window, deadline = now + hourLimit hours
 *   (but capped at window end time, rolling to next day if needed)
 * - If outside regulation window, deadline = next window start + hourLimit hours
 *
 * @param days - Days string ("M-F", "M-Sa", "M-Su")
 * @param hrsBegin - Start time in military format (e.g., 900 = 9:00 AM)
 * @param hrsEnd - End time in military format (e.g., 1800 = 6:00 PM)
 * @param hourLimit - Hour limit (e.g., 2 for 2-hour parking)
 * @param now - Reference time (defaults to current time)
 * @returns The deadline by which the car must be moved
 */
export function nextMoveDeadline(
  days: string,
  hrsBegin: number,
  hrsEnd: number,
  hourLimit: number,
  now?: Date,
): Date {
  const reference = now || new Date();
  const regulatedWeekdays = parseDaysString(days);

  const [beginHour, beginMinute] = parseMilitaryTime(hrsBegin);
  const [endHour, endMinute] = parseMilitaryTime(hrsEnd);

  // Convert our Weekday enum (0=Monday) to JS weekday (0=Sunday)
  // Our enum: Mon=0, Tue=1, Wed=2, Thu=3, Fri=4, Sat=5, Sun=6
  // JS:       Sun=0, Mon=1, Tue=2, Wed=3, Thu=4, Fri=5, Sat=6
  const jsRegulatedDays = new Set<number>();
  for (const weekday of regulatedWeekdays) {
    // Convert: ourWeekday + 1, with Sunday (6) becoming 0
    const jsDay = weekday === Weekday.SUN ? 0 : weekday + 1;
    jsRegulatedDays.add(jsDay);
  }

  /**
   * Find the next regulated day starting from a given date.
   */
  function findNextRegulatedDay(startDate: Date, includeToday: boolean): Date {
    const parts = getPacificDateParts(startDate);
    let { year, month, day } = parts;

    // Create a date for the start of the search day
    let searchDate = createPacificDate(year, month, day, beginHour, beginMinute);

    if (!includeToday) {
      // Move to next day
      searchDate = new Date(searchDate.getTime() + 24 * 60 * 60 * 1000);
    }

    // Search up to 7 days to find a regulated day
    for (let i = 0; i < 7; i++) {
      const jsWeekday = getPacificWeekday(searchDate);
      if (jsRegulatedDays.has(jsWeekday)) {
        // Return start of regulation window on this day
        const searchParts = getPacificDateParts(searchDate);
        return createPacificDate(searchParts.year, searchParts.month, searchParts.day, beginHour, beginMinute);
      }
      searchDate = new Date(searchDate.getTime() + 24 * 60 * 60 * 1000);
    }

    throw new Error('Could not find a regulated day within 7 days');
  }

  // Get current time in Pacific
  const nowParts = getPacificDateParts(reference);
  const currentMinutesSinceMidnight = nowParts.hour * 60 + nowParts.minute;
  const beginMinutesSinceMidnight = beginHour * 60 + beginMinute;
  const endMinutesSinceMidnight = endHour * 60 + endMinute;

  const jsCurrentWeekday = getPacificWeekday(reference);
  const isRegulatedDay = jsRegulatedDays.has(jsCurrentWeekday);

  // Check if currently within the regulation window
  const isWithinWindow =
    isRegulatedDay &&
    currentMinutesSinceMidnight >= beginMinutesSinceMidnight &&
    currentMinutesSinceMidnight < endMinutesSinceMidnight;

  if (isWithinWindow) {
    // Calculate tentative deadline: now + hourLimit hours
    const tentativeDeadline = new Date(reference.getTime() + hourLimit * 60 * 60 * 1000);
    const tentativeParts = getPacificDateParts(tentativeDeadline);
    const tentativeMinutes = tentativeParts.hour * 60 + tentativeParts.minute;

    // Check if tentative deadline is still within today's window
    // (same day and before end time)
    const isSameDay =
      tentativeParts.year === nowParts.year &&
      tentativeParts.month === nowParts.month &&
      tentativeParts.day === nowParts.day;

    if (isSameDay && tentativeMinutes <= endMinutesSinceMidnight) {
      return tentativeDeadline;
    }

    // Deadline exceeds today's window - find next regulated day
    const nextWindowStart = findNextRegulatedDay(reference, false);
    return new Date(nextWindowStart.getTime() + hourLimit * 60 * 60 * 1000);
  }

  // Not within window - check if before or after today's window
  if (isRegulatedDay && currentMinutesSinceMidnight < beginMinutesSinceMidnight) {
    // Before today's window starts - deadline is today's start + hourLimit
    const windowStart = createPacificDate(nowParts.year, nowParts.month, nowParts.day, beginHour, beginMinute);
    return new Date(windowStart.getTime() + hourLimit * 60 * 60 * 1000);
  }

  // After today's window (or non-regulated day) - find next regulated day
  const nextWindowStart = findNextRegulatedDay(reference, false);
  return new Date(nextWindowStart.getTime() + hourLimit * 60 * 60 * 1000);
}
