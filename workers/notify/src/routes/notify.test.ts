import { describe, it, expect } from 'vitest';
import { Hono } from 'hono';
import notify from './notify';

function createTestApp() {
  const app = new Hono<{
    Bindings: {
      SUPABASE_URL: string;
      SUPABASE_KEY: string;
      NOTIFY_RUN_TOKEN?: string;
      NOTIFY_DRY_RUN?: string;
      FCM_SERVICE_ACCOUNT_JSON?: string;
      FCM_PROJECT_ID?: string;
    };
  }>();

  app.route('/internal/notify', notify);
  return app;
}

describe('Notify Endpoints', () => {
  const app = createTestApp();

  it('POST /internal/notify/test-push returns 401 without auth', async () => {
    const env = {
      SUPABASE_URL: 'https://test.supabase.co',
      SUPABASE_KEY: 'test-key',
      NOTIFY_RUN_TOKEN: 'secret-token',
      NOTIFY_DRY_RUN: 'true',
    };

    const req = new Request('http://localhost/internal/notify/test-push', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        device_token: 'a'.repeat(25),
        title: 'Test',
        body: 'Hello',
        dry_run: true,
      }),
    });

    const res = await app.fetch(req, env);
    expect(res.status).toBe(401);
  });

  it('POST /internal/notify/test-push returns 200 in dry-run mode', async () => {
    const env = {
      SUPABASE_URL: 'https://test.supabase.co',
      SUPABASE_KEY: 'test-key',
      NOTIFY_RUN_TOKEN: 'secret-token',
      NOTIFY_DRY_RUN: 'true',
    };

    const req = new Request('http://localhost/internal/notify/test-push', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer secret-token',
      },
      body: JSON.stringify({
        device_token: 'a'.repeat(25),
        title: 'Test',
        body: 'Hello',
        dry_run: true,
      }),
    });

    const res = await app.fetch(req, env);
    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean; dry_run: boolean };
    expect(body.ok).toBe(true);
    expect(body.dry_run).toBe(true);
  });
});
