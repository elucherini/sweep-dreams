import { Hono } from 'hono';
import notify from './routes/notify';
import { runNotificationSweep } from './notify';

type Bindings = {
  SUPABASE_URL: string;
  SUPABASE_KEY: string;
  FCM_SERVICE_ACCOUNT_JSON?: string;
  FCM_PROJECT_ID?: string;
  NOTIFY_CADENCE_MINUTES?: string;
  NOTIFY_DRY_RUN?: string;
  NOTIFY_RUN_TOKEN?: string;
};

const app = new Hono<{ Bindings: Bindings }>();

app.get('/health', (c) => c.json({ status: 'ok' }));
app.route('/internal/notify', notify);

export default {
  fetch: app.fetch,
  scheduled: (_event: ScheduledEvent, env: Bindings, ctx: ExecutionContext) => {
    ctx.waitUntil(
      runNotificationSweep(env).catch((err) => {
        console.error('Notification sweep failed', err);
      }),
    );
  },
};
