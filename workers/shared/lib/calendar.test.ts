import { describe, it, expect } from 'vitest';
import { nextSweepWindow, nextSweepWindowFromRule, parseDaysString, nextMoveDeadline } from './calendar';
import type { SweepingSchedule, RecurringRule } from '../models';
import { Weekday } from '../models';

const PACIFIC_TZ = 'America/Los_Angeles';

function pacificParts(date: Date): { year: number; month: number; day: number; hour: number; minute: number } {
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
  const getValue = (type: string) => Number.parseInt(parts.find(p => p.type === type)?.value || '0', 10);
  return {
    year: getValue('year'),
    month: getValue('month'),
    day: getValue('day'),
    hour: getValue('hour'),
    minute: getValue('minute'),
  };
}

describe('Calendar Logic', () => {
  describe('nextSweepWindow', () => {
    it('should compute next sweep window for 1st Monday', () => {
      const schedule: SweepingSchedule = {
        cnn: 123,
        corridor: 'Main St',
        limits: '100-200',
        cnn_right_left: 'R',
        block_side: 'E',
        full_name: 'Mon 1st 8am-10am',
        week_day: 'Mon',
        from_hour: 8,
        to_hour: 10,
        week1: true,
        week2: false,
        week3: false,
        week4: false,
        week5: false,
        holidays: false,
        block_sweep_id: 456,
        line: [[-122.4194, 37.7749]],
        line_geojson: { type: 'LineString', coordinates: [[-122.4194, 37.7749]] },
      };

      // Test from early January 2025
      const now = new Date('2025-01-01T08:00:00Z'); // Jan 1, 2025 00:00 Pacific
      const [start, end] = nextSweepWindow(schedule, now);
      const startP = pacificParts(start);
      const endP = pacificParts(end);

      // First Monday of Jan 2025 is Jan 6
      expect(startP.day).toBe(6);
      expect(startP.month).toBe(1);
      expect(startP.hour).toBe(8);
      expect(endP.hour).toBe(10);
    });

    it('should handle multiple weeks (1st, 3rd, 5th)', () => {
      const schedule: SweepingSchedule = {
        cnn: 123,
        corridor: 'Main St',
        limits: '100-200',
        cnn_right_left: 'R',
        block_side: 'E',
        full_name: 'Tue 1st, 3rd, 5th 12pm-2pm',
        week_day: 'Tue',
        from_hour: 12,
        to_hour: 14,
        week1: true,
        week2: false,
        week3: true,
        week4: false,
        week5: true,
        holidays: false,
        block_sweep_id: 456,
        line: [[-122.4194, 37.7749]],
        line_geojson: { type: 'LineString', coordinates: [[-122.4194, 37.7749]] },
      };

      // Test from Jan 10, 2025 (after 1st Tuesday)
      const now = new Date('2025-01-10T08:00:00Z'); // Jan 10, 2025 00:00 Pacific
      const [start, end] = nextSweepWindow(schedule, now);
      const startP = pacificParts(start);

      // Should get 3rd Tuesday of January (Jan 21, 2025)
      expect(startP.day).toBe(21);
      expect(startP.month).toBe(1);
    });

    it('should handle midnight-crossing windows', () => {
      const schedule: SweepingSchedule = {
        cnn: 123,
        corridor: 'Main St',
        limits: '100-200',
        cnn_right_left: 'R',
        block_side: 'E',
        full_name: 'Wed 1st 10pm-2am',
        week_day: 'Wed',
        from_hour: 22,
        to_hour: 2,
        week1: true,
        week2: false,
        week3: false,
        week4: false,
        week5: false,
        holidays: false,
        block_sweep_id: 456,
        line: [[-122.4194, 37.7749]],
        line_geojson: { type: 'LineString', coordinates: [[-122.4194, 37.7749]] },
      };

      const now = new Date('2025-01-01T08:00:00Z'); // Jan 1, 2025 00:00 Pacific
      const [start, end] = nextSweepWindow(schedule, now);
      const startP = pacificParts(start);
      const endP = pacificParts(end);

      // First Wednesday of Jan 2025 is Jan 1
      expect(startP.day).toBe(1);
      expect(startP.hour).toBe(22);

      // End should be next day at 2am
      expect(endP.day).toBe(2);
      expect(endP.hour).toBe(2);
    });

    it('should throw error for holiday-only schedules', () => {
      const schedule: SweepingSchedule = {
        cnn: 123,
        corridor: 'Main St',
        limits: '100-200',
        cnn_right_left: 'R',
        block_side: 'E',
        full_name: 'Holiday',
        week_day: 'Holiday',
        from_hour: 8,
        to_hour: 10,
        week1: false,
        week2: false,
        week3: false,
        week4: false,
        week5: false,
        holidays: true,
        block_sweep_id: 456,
        line: [[-122.4194, 37.7749]],
        line_geojson: { type: 'LineString', coordinates: [[-122.4194, 37.7749]] },
      };

      const now = new Date('2025-01-01T08:00:00Z'); // Jan 1, 2025 00:00 Pacific
      expect(() => nextSweepWindow(schedule, now)).toThrow('holiday');
    });

    it('should throw error for schedules with no active weeks', () => {
      const schedule: SweepingSchedule = {
        cnn: 123,
        corridor: 'Main St',
        limits: '100-200',
        cnn_right_left: 'R',
        block_side: 'E',
        full_name: 'Mon (no weeks)',
        week_day: 'Mon',
        from_hour: 8,
        to_hour: 10,
        week1: false,
        week2: false,
        week3: false,
        week4: false,
        week5: false,
        holidays: false,
        block_sweep_id: 456,
        line: [[-122.4194, 37.7749]],
        line_geojson: { type: 'LineString', coordinates: [[-122.4194, 37.7749]] },
      };

      const now = new Date('2025-01-01T08:00:00Z'); // Jan 1, 2025 00:00 Pacific
      expect(() => nextSweepWindow(schedule, now)).toThrow('no active weeks');
    });
  });

  describe('nextSweepWindowFromRule', () => {
    it('should compute next sweep window from recurring rule', () => {
      const rule: RecurringRule = {
        pattern: {
          weekdays: [Weekday.MON],
          weeks_of_month: [1],
        },
        time_window: {
          start: '08:00',
          end: '10:00',
        },
        skip_holidays: false,
      };

      const now = new Date('2025-01-01T08:00:00Z'); // Jan 1, 2025 00:00 Pacific
      const [start, end] = nextSweepWindowFromRule(rule, now);
      const startP = pacificParts(start);
      const endP = pacificParts(end);

      // First Monday of Jan 2025 is Jan 6
      expect(startP.day).toBe(6);
      expect(startP.month).toBe(1);
      expect(startP.hour).toBe(8);
      expect(endP.hour).toBe(10);
    });

    it('should handle null weeks_of_month (all weeks)', () => {
      const rule: RecurringRule = {
        pattern: {
          weekdays: [Weekday.FRI],
          weeks_of_month: null,
        },
        time_window: {
          start: '14:00',
          end: '16:00',
        },
        skip_holidays: false,
      };

      const now = new Date('2025-01-01T08:00:00Z'); // Jan 1, 2025 00:00 Pacific
      const [start, end] = nextSweepWindowFromRule(rule, now);
      const startP = pacificParts(start);
      const endP = pacificParts(end);

      // First Friday of Jan 2025 is Jan 3
      expect(startP.day).toBe(3);
      expect(startP.month).toBe(1);
      expect(startP.hour).toBe(14);
      expect(endP.hour).toBe(16);
    });

    it('should throw error for rule with no weekdays', () => {
      const rule: RecurringRule = {
        pattern: {
          weekdays: [],
          weeks_of_month: [1],
        },
        time_window: {
          start: '08:00',
          end: '10:00',
        },
        skip_holidays: false,
      };

      const now = new Date('2025-01-01T08:00:00Z'); // Jan 1, 2025 00:00 Pacific
      expect(() => nextSweepWindowFromRule(rule, now)).toThrow('no weekdays');
    });
  });

  describe('parseDaysString', () => {
    it('should parse M-F correctly', () => {
      const days = parseDaysString('M-F');
      expect(days).toEqual(new Set([Weekday.MON, Weekday.TUE, Weekday.WED, Weekday.THU, Weekday.FRI]));
    });

    it('should parse M-Sa correctly', () => {
      const days = parseDaysString('M-Sa');
      expect(days).toEqual(new Set([Weekday.MON, Weekday.TUE, Weekday.WED, Weekday.THU, Weekday.FRI, Weekday.SAT]));
    });

    it('should parse M-Su correctly', () => {
      const days = parseDaysString('M-Su');
      expect(days).toEqual(new Set([Weekday.MON, Weekday.TUE, Weekday.WED, Weekday.THU, Weekday.FRI, Weekday.SAT, Weekday.SUN]));
    });

    it('should be case-insensitive', () => {
      expect(parseDaysString('m-f')).toEqual(parseDaysString('M-F'));
      expect(parseDaysString('m-sa')).toEqual(parseDaysString('M-Sa'));
      expect(parseDaysString('m-su')).toEqual(parseDaysString('M-Su'));
    });

    it('should throw error for unknown pattern', () => {
      expect(() => parseDaysString('Mon-Fri')).toThrow('Unknown days pattern');
    });
  });

  describe('nextMoveDeadline', () => {
    // All tests use Pacific time. January 2026 calendar:
    // Sun Mon Tue Wed Thu Fri Sat
    //                   1   2   3
    //   4   5   6   7   8   9  10
    //  11  12  13  14  15  16  17
    //  18  19  20  21  22  23  24
    //  25  26  27  28  29  30  31

    // Helper to create a Date in Pacific time
    // January is PST (UTC-8)
    const pacificDate = (year: number, month: number, day: number, hour: number, minute: number = 0) => {
      return new Date(`${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}T${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}:00-08:00`);
    };

    // Test Case 1: Within regulation window, deadline within same day
    it('should return same-day deadline when within window and deadline fits', () => {
      // Friday Jan 9, 2026 at 2:00 PM, M-F 9am-6pm, 2-hour limit
      const now = pacificDate(2026, 1, 9, 14, 0);  // Friday 2pm
      const deadline = nextMoveDeadline('M-F', 900, 1800, 2, now);

      // Expected: Friday 4:00 PM (2pm + 2h = 4pm, before 6pm)
      expect(deadline.getTime()).toBe(pacificDate(2026, 1, 9, 16, 0).getTime());
    });

    // Test Case 2: Within regulation window, deadline exceeds end time
    it('should roll to next regulated day when deadline exceeds window end', () => {
      // Friday Jan 9, 2026 at 5:00 PM, M-F 9am-6pm, 2-hour limit
      const now = pacificDate(2026, 1, 9, 17, 0);  // Friday 5pm
      const deadline = nextMoveDeadline('M-F', 900, 1800, 2, now);

      // Expected: Monday Jan 12 at 11:00 AM (next regulated day 9am + 2h)
      expect(deadline.getTime()).toBe(pacificDate(2026, 1, 12, 11, 0).getTime());
    });

    // Test Case 3: Non-regulated day (weekend)
    it('should return next regulated day deadline on weekend', () => {
      // Saturday Jan 10, 2026 at 2:00 PM, M-F 9am-6pm, 2-hour limit
      const now = pacificDate(2026, 1, 10, 14, 0);  // Saturday 2pm
      const deadline = nextMoveDeadline('M-F', 900, 1800, 2, now);

      // Expected: Monday Jan 12 at 11:00 AM (next regulated day 9am + 2h)
      expect(deadline.getTime()).toBe(pacificDate(2026, 1, 12, 11, 0).getTime());
    });

    // Test Case 4: Before regulation hours on a regulated day
    it('should return same-day deadline when before window starts', () => {
      // Monday Jan 5, 2026 at 7:00 AM, M-F 9am-6pm, 2-hour limit
      const now = pacificDate(2026, 1, 5, 7, 0);  // Monday 7am
      const deadline = nextMoveDeadline('M-F', 900, 1800, 2, now);

      // Expected: Monday Jan 5 at 11:00 AM (9am + 2h)
      expect(deadline.getTime()).toBe(pacificDate(2026, 1, 5, 11, 0).getTime());
    });

    // Test Case 5: After regulation hours on a regulated day
    it('should return next day deadline when after window ends', () => {
      // Monday Jan 5, 2026 at 7:00 PM, M-F 9am-6pm, 2-hour limit
      const now = pacificDate(2026, 1, 5, 19, 0);  // Monday 7pm
      const deadline = nextMoveDeadline('M-F', 900, 1800, 2, now);

      // Expected: Tuesday Jan 6 at 11:00 AM (next day 9am + 2h)
      expect(deadline.getTime()).toBe(pacificDate(2026, 1, 6, 11, 0).getTime());
    });

    // Test Case 6: Friday after hours → skip weekend
    it('should skip weekend when Friday after hours', () => {
      // Friday Jan 9, 2026 at 7:00 PM, M-F 9am-6pm, 2-hour limit
      const now = pacificDate(2026, 1, 9, 19, 0);  // Friday 7pm
      const deadline = nextMoveDeadline('M-F', 900, 1800, 2, now);

      // Expected: Monday Jan 12 at 11:00 AM
      expect(deadline.getTime()).toBe(pacificDate(2026, 1, 12, 11, 0).getTime());
    });

    // Test Case 7: Different hour limit (4 hours)
    it('should handle 4-hour limit correctly', () => {
      // Wednesday Jan 7, 2026 at 10:00 AM, M-F 8am-6pm, 4-hour limit
      const now = pacificDate(2026, 1, 7, 10, 0);  // Wednesday 10am
      const deadline = nextMoveDeadline('M-F', 800, 1800, 4, now);

      // Expected: Wednesday Jan 7 at 2:00 PM (10am + 4h = 2pm, before 6pm)
      expect(deadline.getTime()).toBe(pacificDate(2026, 1, 7, 14, 0).getTime());
    });

    // Test Case 8: Hour limit exceeds remaining time in window
    it('should roll to next day when hour limit exceeds remaining window time', () => {
      // Wednesday Jan 7, 2026 at 3:00 PM, M-F 8am-6pm, 4-hour limit
      const now = pacificDate(2026, 1, 7, 15, 0);  // Wednesday 3pm
      const deadline = nextMoveDeadline('M-F', 800, 1800, 4, now);

      // Expected: Thursday Jan 8 at 12:00 PM (3pm + 4h = 7pm > 6pm, so next day 8am + 4h = 12pm)
      expect(deadline.getTime()).toBe(pacificDate(2026, 1, 8, 12, 0).getTime());
    });

    // Test Case 9: M-Sa regulation (includes Saturday)
    it('should include Saturday for M-Sa regulation', () => {
      // Friday Jan 9, 2026 at 7:00 PM, M-Sa 9am-6pm, 2-hour limit
      const now = pacificDate(2026, 1, 9, 19, 0);  // Friday 7pm
      const deadline = nextMoveDeadline('M-Sa', 900, 1800, 2, now);

      // Expected: Saturday Jan 10 at 11:00 AM (Saturday is regulated)
      expect(deadline.getTime()).toBe(pacificDate(2026, 1, 10, 11, 0).getTime());
    });

    // Test Case 10: M-Su regulation (all days)
    it('should work on weekends for M-Su regulation', () => {
      // Saturday Jan 10, 2026 at 2:00 PM, M-Su 9am-6pm, 2-hour limit
      const now = pacificDate(2026, 1, 10, 14, 0);  // Saturday 2pm
      const deadline = nextMoveDeadline('M-Su', 900, 1800, 2, now);

      // Expected: Saturday Jan 10 at 4:00 PM (2pm + 2h = 4pm)
      expect(deadline.getTime()).toBe(pacificDate(2026, 1, 10, 16, 0).getTime());
    });

    // Test Case 11: Edge case - exactly at start time
    it('should handle exactly at window start time', () => {
      // Monday Jan 5, 2026 at 9:00 AM, M-F 9am-6pm, 2-hour limit
      const now = pacificDate(2026, 1, 5, 9, 0);  // Monday 9am
      const deadline = nextMoveDeadline('M-F', 900, 1800, 2, now);

      // Expected: Monday Jan 5 at 11:00 AM (9am + 2h)
      expect(deadline.getTime()).toBe(pacificDate(2026, 1, 5, 11, 0).getTime());
    });

    // Test Case 12: Edge case - exactly at end time minus hour limit
    it('should handle exactly at end time minus hour limit', () => {
      // Monday Jan 5, 2026 at 4:00 PM, M-F 9am-6pm, 2-hour limit
      const now = pacificDate(2026, 1, 5, 16, 0);  // Monday 4pm
      const deadline = nextMoveDeadline('M-F', 900, 1800, 2, now);

      // Expected: Monday Jan 5 at 6:00 PM (4pm + 2h = 6pm, exactly at end)
      expect(deadline.getTime()).toBe(pacificDate(2026, 1, 5, 18, 0).getTime());
    });

    // Test Case 13: Edge case - one minute before deadline would exceed
    it('should roll to next day when deadline exceeds by one minute', () => {
      // Monday Jan 5, 2026 at 4:01 PM, M-F 9am-6pm, 2-hour limit
      const now = pacificDate(2026, 1, 5, 16, 1);  // Monday 4:01pm
      const deadline = nextMoveDeadline('M-F', 900, 1800, 2, now);

      // Expected: Tuesday Jan 6 at 11:00 AM (4:01pm + 2h = 6:01pm > 6pm)
      expect(deadline.getTime()).toBe(pacificDate(2026, 1, 6, 11, 0).getTime());
    });

    // Test Sunday handling for M-Su
    it('should handle Sunday correctly in M-Su regulation', () => {
      // Sunday Jan 11, 2026 at 2:00 PM, M-Su 9am-6pm, 2-hour limit
      const now = pacificDate(2026, 1, 11, 14, 0);  // Sunday 2pm
      const deadline = nextMoveDeadline('M-Su', 900, 1800, 2, now);

      // Expected: Sunday Jan 11 at 4:00 PM (2pm + 2h = 4pm)
      expect(deadline.getTime()).toBe(pacificDate(2026, 1, 11, 16, 0).getTime());
    });
  });
});
