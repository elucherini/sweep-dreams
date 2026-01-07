import { describe, it, expect, vi, beforeEach } from 'vitest';
import { Hono } from 'hono';
import schedules from './schedules';
import type { SweepingSchedule } from '../models';

const mockFetch = vi.fn();
vi.stubGlobal('fetch', mockFetch);

type CheckLocationSchedule = {
  next_sweep_start: string;
  next_sweep_end: string;
};

type CheckLocationResponse = {
  timezone: string;
  schedules: CheckLocationSchedule[];
};

function createTestApp() {
  const app = new Hono<{
    Bindings: {
      SUPABASE_URL: string;
      SUPABASE_KEY: string;
    };
  }>();

  app.route('', schedules);
  return app;
}

describe('Schedule Endpoints', () => {
  const app = createTestApp();
  const env = {
    SUPABASE_URL: 'https://test.supabase.co',
    SUPABASE_KEY: 'test-key',
  };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('GET /check-location', () => {
    it('returns sweep window in Pacific time (not UTC Z)', async () => {
      const sampleSchedule: SweepingSchedule = {
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
        distance_meters: 10,
        is_user_side: true,
        line_geojson: {
          type: 'LineString',
          coordinates: [[-122.4194, 37.7749]],
        },
      };

      mockFetch.mockImplementation((url: string) => {
        if (url.includes('/rest/v1/rpc/')) {
          return Promise.resolve({
            ok: true,
            json: () => Promise.resolve([sampleSchedule]),
          });
        }
        return Promise.reject(new Error('Unexpected URL'));
      });

      const req = new Request(
        'http://localhost/check-location?latitude=37.7749&longitude=-122.4194',
        { method: 'GET' },
      );

      const res = await app.fetch(req, env);
      expect(res.status).toBe(200);

      const body = (await res.json()) as CheckLocationResponse;
      expect(body.timezone).toBe('America/Los_Angeles');
      expect(body.schedules).toHaveLength(1);

      expect(body.schedules[0].next_sweep_start).toMatch(
        /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}-0[78]:00$/,
      );
      expect(body.schedules[0].next_sweep_end).toMatch(
        /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}-0[78]:00$/,
      );
    });
  });
});

