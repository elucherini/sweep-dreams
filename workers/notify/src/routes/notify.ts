import { Hono } from 'hono';
import { z } from 'zod';
import { zValidator } from '@hono/zod-validator';
import { runNotificationSweep } from '../notify';
import { getFcmAccessToken, loadServiceAccountFromEnv, sendPushV1 } from '../../../shared/lib/fcm';

type Bindings = {
  SUPABASE_URL: string;
  SUPABASE_KEY: string;
  FCM_SERVICE_ACCOUNT_JSON?: string;
  FCM_PROJECT_ID?: string;
  NOTIFY_CADENCE_MINUTES?: string;
  NOTIFY_DRY_RUN?: string;
  NOTIFY_RUN_TOKEN?: string;
};

const notify = new Hono<{ Bindings: Bindings }>();

function isAuthorized(c: { req: { header(name: string): string | undefined }; env: Bindings }): boolean {
  const configured = (c.env.NOTIFY_RUN_TOKEN || '').trim();
  if (!configured) return false;
  const header = c.req.header('authorization') || c.req.header('Authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice('Bearer '.length).trim() : header.trim();
  return token.length > 0 && token === configured;
}

// POST /internal/notify/run
notify.post('/run', async (c) => {
  if (!isAuthorized(c)) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const result = await runNotificationSweep(c.env);
  return c.json(result, 200);
});

const testPushSchema = z.object({
  device_token: z.string().min(20),
  title: z.string().min(1).default('🧹 Test notification'),
  body: z.string().min(1).default('This is a test push from Sweep Dreams!'),
  dry_run: z.boolean().default(false),
});

// POST /internal/notify/test-push
notify.post(
  '/test-push',
  zValidator('json', testPushSchema),
  async (c) => {
    if (!isAuthorized(c)) {
      return c.json({ error: 'Unauthorized' }, 401);
    }

    const payload = c.req.valid('json');
    const rawSa = (c.env.FCM_SERVICE_ACCOUNT_JSON || '').trim();
    const dryRun = payload.dry_run || (c.env.NOTIFY_DRY_RUN || '').trim().toLowerCase() === 'true' || !rawSa;

    if (!rawSa && !dryRun) {
      return c.json({ error: 'FCM_SERVICE_ACCOUNT_JSON is required' }, 500);
    }

    const serviceAccount = rawSa ? loadServiceAccountFromEnv(rawSa, c.env.FCM_PROJECT_ID) : null;
    const accessToken = serviceAccount && !dryRun ? await getFcmAccessToken(serviceAccount) : '';

    await sendPushV1({
      accessToken,
      projectId: serviceAccount?.projectId || '',
      deviceToken: payload.device_token,
      title: payload.title,
      body: payload.body,
      data: { test: 'true' },
      dryRun,
    });

    return c.json({
      ok: true,
      dry_run: dryRun,
      device_token_suffix: payload.device_token.slice(-10),
      project_id: serviceAccount?.projectId || null,
    }, 200);
  },
);

export default notify;
