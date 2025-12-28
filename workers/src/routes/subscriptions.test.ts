import { describe, it, expect, vi, beforeEach } from 'vitest';
import { Hono } from 'hono';
import subscriptions from './subscriptions';
import type { SweepingSchedule, SubscriptionRecord } from '../models';

// Mock fetch globally
const mockFetch = vi.fn();
vi.stubGlobal('fetch', mockFetch);

// Response body types
interface SingleSubscriptionResponse {
  device_token: string;
  platform: string;
  schedule_block_sweep_id: number;
  lead_minutes: number;
  next_sweep_start?: string;
  next_sweep_end?: string;
  error?: string;
}

interface SubscriptionItem {
  schedule_block_sweep_id: number;
  lead_minutes: number;
  corridor: string | null;
  limits: string | null;
  block_side: string | null;
  next_sweep_start: string | null;
  next_sweep_end: string | null;
  error?: string;
}

interface MultipleSubscriptionsResponse {
  device_token: string;
  platform: string;
  subscriptions: SubscriptionItem[];
  error?: string;
}

type ErrorResponse = {
  error: string;
}

// Sample schedule for testing
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
  week2: true,
  week3: true,
  week4: true,
  week5: false,
  holidays: false,
  block_sweep_id: 12345,
  line: [[-122.4194, 37.7749]],
};

// Sample subscription record
const sampleSubscription: SubscriptionRecord = {
  device_token: 'test-token-123',
  platform: 'ios',
  schedule_block_sweep_id: 12345,
  lead_minutes: 60,
  last_notified_at: null,
};

// Create test app with bindings
function createTestApp() {
  const app = new Hono<{
    Bindings: {
      SUPABASE_URL: string;
      SUPABASE_KEY: string;
    };
  }>();

  // Mount subscriptions routes
  app.route('/subscriptions', subscriptions);

  return app;
}

describe('Subscription Endpoints', () => {
  const app = createTestApp();
  const env = {
    SUPABASE_URL: 'https://test.supabase.co',
    SUPABASE_KEY: 'test-key',
  };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('POST /subscriptions', () => {
    it('should create new subscription and return 201 with schedule info', async () => {
      // Mock upsert response
      mockFetch.mockImplementation((url: string) => {
        if (url.includes('/rest/v1/subscriptions')) {
          return Promise.resolve({
            ok: true,
            json: () => Promise.resolve([sampleSubscription]),
          });
        }
        // Mock schedule fetch
        if (url.includes('/rest/v1/schedules')) {
          return Promise.resolve({
            ok: true,
            json: () => Promise.resolve([sampleSchedule]),
          });
        }
        return Promise.reject(new Error('Unexpected URL'));
      });

      const req = new Request('http://localhost/subscriptions', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          device_token: 'test-token-123',
          platform: 'ios',
          schedule_block_sweep_id: 12345,
          latitude: 37.7749,
          longitude: -122.4194,
          lead_minutes: 60,
        }),
      });

      const res = await app.fetch(req, env);
      expect(res.status).toBe(201);

      const body = (await res.json()) as SingleSubscriptionResponse;
      expect(body.device_token).toBe('test-token-123');
      expect(body.platform).toBe('ios');
      expect(body.schedule_block_sweep_id).toBe(12345);
      expect(body.lead_minutes).toBe(60);
      expect(body.next_sweep_start).toBeDefined();
      expect(body.next_sweep_end).toBeDefined();
    });

    it('should update existing subscription (upsert behavior)', async () => {
      // Same as create - upsert returns updated record
      mockFetch.mockImplementation((url: string) => {
        if (url.includes('/rest/v1/subscriptions')) {
          return Promise.resolve({
            ok: true,
            json: () =>
              Promise.resolve([
                { ...sampleSubscription, lead_minutes: 120 },
              ]),
          });
        }
        if (url.includes('/rest/v1/schedules')) {
          return Promise.resolve({
            ok: true,
            json: () => Promise.resolve([sampleSchedule]),
          });
        }
        return Promise.reject(new Error('Unexpected URL'));
      });

      const req = new Request('http://localhost/subscriptions', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          device_token: 'test-token-123',
          platform: 'ios',
          schedule_block_sweep_id: 12345,
          latitude: 37.7749,
          longitude: -122.4194,
          lead_minutes: 120,
        }),
      });

      const res = await app.fetch(req, env);
      expect(res.status).toBe(201);

      const body = (await res.json()) as SingleSubscriptionResponse;
      expect(body.lead_minutes).toBe(120);
    });

    it('should return 404 if schedule_block_sweep_id does not exist', async () => {
      mockFetch.mockImplementation((url: string) => {
        if (url.includes('/rest/v1/subscriptions')) {
          return Promise.resolve({
            ok: true,
            json: () => Promise.resolve([sampleSubscription]),
          });
        }
        if (url.includes('/rest/v1/schedules')) {
          return Promise.resolve({
            ok: true,
            json: () => Promise.resolve([]), // Empty - schedule not found
          });
        }
        return Promise.reject(new Error('Unexpected URL'));
      });

      const req = new Request('http://localhost/subscriptions', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          device_token: 'test-token-123',
          platform: 'ios',
          schedule_block_sweep_id: 99999,
          latitude: 37.7749,
          longitude: -122.4194,
          lead_minutes: 60,
        }),
      });

      const res = await app.fetch(req, env);
      expect(res.status).toBe(404);

      const body = (await res.json()) as ErrorResponse;
      expect(body.error).toBe('Schedule not found');
    });

    it('should return 400 for invalid lead_minutes (not multiple of 15)', async () => {
      const req = new Request('http://localhost/subscriptions', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          device_token: 'test-token-123',
          platform: 'ios',
          schedule_block_sweep_id: 12345,
          latitude: 37.7749,
          longitude: -122.4194,
          lead_minutes: 17, // Not multiple of 15
        }),
      });

      const res = await app.fetch(req, env);
      expect(res.status).toBe(400);
    });

    it('should return 400 for missing required fields', async () => {
      const req = new Request('http://localhost/subscriptions', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          device_token: 'test-token-123',
          // Missing platform, schedule_block_sweep_id, etc.
        }),
      });

      const res = await app.fetch(req, env);
      expect(res.status).toBe(400);
    });

    it('should return 400 for invalid platform', async () => {
      const req = new Request('http://localhost/subscriptions', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          device_token: 'test-token-123',
          platform: 'windows', // Invalid
          schedule_block_sweep_id: 12345,
          latitude: 37.7749,
          longitude: -122.4194,
          lead_minutes: 60,
        }),
      });

      const res = await app.fetch(req, env);
      expect(res.status).toBe(400);
    });

    it('should return 409 when subscription limit is exceeded', async () => {
      mockFetch.mockImplementation((url: string) => {
        if (url.includes('/rest/v1/subscriptions')) {
          return Promise.resolve({
            ok: false,
            status: 400,
            text: () => Promise.resolve('{"code":"P0001","message":"Maximum subscriptions (5) per device exceeded"}'),
          });
        }
        return Promise.reject(new Error('Unexpected URL'));
      });

      const req = new Request('http://localhost/subscriptions', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          device_token: 'test-token-123',
          platform: 'ios',
          schedule_block_sweep_id: 12345,
          latitude: 37.7749,
          longitude: -122.4194,
          lead_minutes: 60,
        }),
      });

      const res = await app.fetch(req, env);
      expect(res.status).toBe(409);

      const body = (await res.json()) as ErrorResponse;
      expect(body.error).toBe('Maximum subscriptions limit reached');
    });
  });

  describe('GET /subscriptions/:device_token', () => {
    it('should return all subscriptions with computed next sweep', async () => {
      mockFetch.mockImplementation((url: string) => {
        if (url.includes('/rest/v1/subscriptions')) {
          return Promise.resolve({
            ok: true,
            json: () => Promise.resolve([sampleSubscription]),
          });
        }
        if (url.includes('/rest/v1/schedules')) {
          return Promise.resolve({
            ok: true,
            json: () => Promise.resolve([sampleSchedule]),
          });
        }
        return Promise.reject(new Error('Unexpected URL'));
      });

      const req = new Request(
        'http://localhost/subscriptions/test-token-123',
        { method: 'GET' }
      );

      const res = await app.fetch(req, env);
      expect(res.status).toBe(200);

      const body = (await res.json()) as MultipleSubscriptionsResponse;
      expect(body.device_token).toBe('test-token-123');
      expect(body.platform).toBe('ios');
      expect(body.subscriptions).toHaveLength(1);
      expect(body.subscriptions[0].schedule_block_sweep_id).toBe(12345);
      expect(body.subscriptions[0].lead_minutes).toBe(60);
      expect(body.subscriptions[0].next_sweep_start).toBeDefined();
      expect(body.subscriptions[0].next_sweep_end).toBeDefined();
    });

    it('should return 404 for unknown device token', async () => {
      mockFetch.mockImplementation((url: string) => {
        if (url.includes('/rest/v1/subscriptions')) {
          return Promise.resolve({
            ok: true,
            json: () => Promise.resolve([]), // Empty - not found
          });
        }
        return Promise.reject(new Error('Unexpected URL'));
      });

      const req = new Request(
        'http://localhost/subscriptions/unknown-token',
        { method: 'GET' }
      );

      const res = await app.fetch(req, env);
      expect(res.status).toBe(404);

      const body = (await res.json()) as ErrorResponse;
      expect(body.error).toBe('No subscriptions found');
    });

    it('should return subscription with error if schedule no longer exists', async () => {
      mockFetch.mockImplementation((url: string) => {
        if (url.includes('/rest/v1/subscriptions')) {
          return Promise.resolve({
            ok: true,
            json: () => Promise.resolve([sampleSubscription]),
          });
        }
        if (url.includes('/rest/v1/schedules')) {
          return Promise.resolve({
            ok: true,
            json: () => Promise.resolve([]), // Schedule deleted
          });
        }
        return Promise.reject(new Error('Unexpected URL'));
      });

      const req = new Request(
        'http://localhost/subscriptions/test-token-123',
        { method: 'GET' }
      );

      const res = await app.fetch(req, env);
      // Now returns 200 with subscription that has error field
      expect(res.status).toBe(200);

      const body = (await res.json()) as MultipleSubscriptionsResponse;
      expect(body.subscriptions).toHaveLength(1);
      expect(body.subscriptions[0].error).toBe('Schedule not found');
      expect(body.subscriptions[0].corridor).toBeNull();
    });
  });

  describe('DELETE /subscriptions/:device_token', () => {
    it('should remove all subscriptions and return 204', async () => {
      mockFetch.mockImplementation((url: string) => {
        if (url.includes('/rest/v1/subscriptions')) {
          return Promise.resolve({
            ok: true,
            json: () => Promise.resolve([sampleSubscription]), // Deleted record returned
          });
        }
        return Promise.reject(new Error('Unexpected URL'));
      });

      const req = new Request(
        'http://localhost/subscriptions/test-token-123',
        { method: 'DELETE' }
      );

      const res = await app.fetch(req, env);
      expect(res.status).toBe(204);
    });

    it('should return 404 for unknown device token', async () => {
      mockFetch.mockImplementation((url: string) => {
        if (url.includes('/rest/v1/subscriptions')) {
          return Promise.resolve({
            ok: true,
            json: () => Promise.resolve([]), // Empty - nothing deleted
          });
        }
        return Promise.reject(new Error('Unexpected URL'));
      });

      const req = new Request(
        'http://localhost/subscriptions/unknown-token',
        { method: 'DELETE' }
      );

      const res = await app.fetch(req, env);
      expect(res.status).toBe(404);

      const body = (await res.json()) as ErrorResponse;
      expect(body.error).toBe('No subscriptions found');
    });
  });

  describe('DELETE /subscriptions/:device_token/:schedule_block_sweep_id', () => {
    it('should remove specific subscription and return 204', async () => {
      mockFetch.mockImplementation((url: string) => {
        if (url.includes('/rest/v1/subscriptions')) {
          return Promise.resolve({
            ok: true,
            json: () => Promise.resolve([sampleSubscription]),
          });
        }
        return Promise.reject(new Error('Unexpected URL'));
      });

      const req = new Request(
        'http://localhost/subscriptions/test-token-123/12345',
        { method: 'DELETE' }
      );

      const res = await app.fetch(req, env);
      expect(res.status).toBe(204);
    });

    it('should return 404 for unknown subscription', async () => {
      mockFetch.mockImplementation((url: string) => {
        if (url.includes('/rest/v1/subscriptions')) {
          return Promise.resolve({
            ok: true,
            json: () => Promise.resolve([]),
          });
        }
        return Promise.reject(new Error('Unexpected URL'));
      });

      const req = new Request(
        'http://localhost/subscriptions/test-token-123/99999',
        { method: 'DELETE' }
      );

      const res = await app.fetch(req, env);
      expect(res.status).toBe(404);

      const body = (await res.json()) as ErrorResponse;
      expect(body.error).toBe('Subscription not found');
    });

    it('should return 400 for invalid schedule_block_sweep_id', async () => {
      const req = new Request(
        'http://localhost/subscriptions/test-token-123/invalid',
        { method: 'DELETE' }
      );

      const res = await app.fetch(req, env);
      expect(res.status).toBe(400);

      const body = (await res.json()) as ErrorResponse;
      expect(body.error).toBe('Invalid schedule_block_sweep_id');
    });
  });
});
