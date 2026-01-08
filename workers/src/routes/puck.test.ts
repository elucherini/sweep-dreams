import { describe, it, expect, vi, beforeEach } from 'vitest';
import { Hono } from 'hono';
import puck from './puck';
import type { SweepingSchedule } from '../models';
import type { ParkingRegulation } from '../models/parking';

const mockFetch = vi.fn();
vi.stubGlobal('fetch', mockFetch);

function createTestApp() {
  const app = new Hono<{
    Bindings: {
      SUPABASE_URL: string;
      SUPABASE_KEY: string;
    };
  }>();

  app.route('', puck);
  return app;
}

describe('Puck Endpoint', () => {
  const app = createTestApp();
  const env = {
    SUPABASE_URL: 'https://test.supabase.co',
    SUPABASE_KEY: 'test-key',
  };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('prefers user-side schedule and returns nearest regulation', async () => {
    const scheduleRight: SweepingSchedule = {
      cnn: 123,
      corridor: 'Main St',
      limits: '100-200',
      cnn_right_left: 'R',
      block_side: 'East',
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
      block_sweep_id: 111,
      line: [[-122.4194, 37.7749]],
      distance_meters: 5,
      is_user_side: true,
      line_geojson: {
        type: 'LineString',
        coordinates: [[-122.4194, 37.7749]],
      },
    };

    const scheduleLeft: SweepingSchedule = {
      ...scheduleRight,
      cnn_right_left: 'L',
      block_side: 'West',
      block_sweep_id: 222,
      is_user_side: false,
    };

    const regulation: ParkingRegulation = {
      id: 999,
      regulation: '2 HR PARKING',
      days: 'Mon-Fri',
      hrs_begin: 900,
      hrs_end: 1800,
      hour_limit: 2,
      rpp_area1: null,
      rpp_area2: null,
      exceptions: null,
      from_time: '9am',
      to_time: '6pm',
      neighborhood: null,
      line: { type: 'MultiLineString', coordinates: [[[-122.4194, 37.7749]]] },
      distance_meters: 3,
    };

    mockFetch.mockImplementation((url: string) => {
      if (url.includes('/rest/v1/rpc/schedules_near_closest_block')) {
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve([scheduleRight, scheduleLeft]),
        });
      }
      if (url.includes('/rest/v1/rpc/parking_regulation_nearest')) {
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve([regulation]),
        });
      }
      return Promise.reject(new Error(`Unexpected URL: ${url}`));
    });

    const req = new Request(
      'http://localhost/check-puck?latitude=37.7749&longitude=-122.4194',
      { method: 'GET' },
    );

    const res = await app.fetch(req, env);
    expect(res.status).toBe(200);
    const body = await res.json() as any;

    expect(body.schedule).toBeTruthy();
    expect(body.schedule.is_user_side).toBe(true);
    expect(body.schedule.cnn_right_left).toBe('R');

    expect(body.regulation).toBeTruthy();
    expect(body.regulation.id).toBe(999);
    expect(body.regulation.distance_meters).toBe(3);
  });
});

