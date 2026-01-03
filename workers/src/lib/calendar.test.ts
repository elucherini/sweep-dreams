import { describe, it, expect } from 'vitest';
import { nextSweepWindow, nextSweepWindowFromRule } from './calendar';
import type { SweepingSchedule, RecurringRule } from '../models';
import { Weekday } from '../models';

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
      const now = new Date('2025-01-01T00:00:00Z');
      const [start, end] = nextSweepWindow(schedule, now);

      // First Monday of Jan 2025 is Jan 6
      expect(start.getDate()).toBe(6);
      expect(start.getMonth()).toBe(0); // 0 = January
      expect(start.getHours()).toBe(8);
      expect(end.getHours()).toBe(10);
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
      const now = new Date('2025-01-10T00:00:00Z');
      const [start, end] = nextSweepWindow(schedule, now);

      // Should get 3rd Tuesday of January (Jan 21, 2025)
      expect(start.getDate()).toBe(21);
      expect(start.getMonth()).toBe(0);
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

      const now = new Date('2025-01-01T00:00:00Z');
      const [start, end] = nextSweepWindow(schedule, now);

      // First Wednesday of Jan 2025 is Jan 1
      expect(start.getDate()).toBe(1);
      expect(start.getHours()).toBe(22);

      // End should be next day at 2am
      expect(end.getDate()).toBe(2);
      expect(end.getHours()).toBe(2);
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

      const now = new Date('2025-01-01T00:00:00Z');
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

      const now = new Date('2025-01-01T00:00:00Z');
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

      const now = new Date('2025-01-01T00:00:00Z');
      const [start, end] = nextSweepWindowFromRule(rule, now);

      // First Monday of Jan 2025 is Jan 6
      expect(start.getDate()).toBe(6);
      expect(start.getMonth()).toBe(0);
      expect(start.getHours()).toBe(8);
      expect(end.getHours()).toBe(10);
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

      const now = new Date('2025-01-01T00:00:00Z');
      const [start, end] = nextSweepWindowFromRule(rule, now);

      // First Friday of Jan 2025 is Jan 3
      expect(start.getDate()).toBe(3);
      expect(start.getMonth()).toBe(0);
      expect(start.getHours()).toBe(14);
      expect(end.getHours()).toBe(16);
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

      const now = new Date('2025-01-01T00:00:00Z');
      expect(() => nextSweepWindowFromRule(rule, now)).toThrow('no weekdays');
    });
  });
});
