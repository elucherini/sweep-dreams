import { Hono } from 'hono';
import { cors } from 'hono/cors';
import schedules from './routes/schedules';
import subscriptions from './routes/subscriptions';

type Bindings = {
  SUPABASE_URL: string;
  SUPABASE_KEY: string;
};

const app = new Hono<{ Bindings: Bindings }>();

// CORS middleware
app.use('/*', cors({
  origin: '*',  // TODO: Restrict to your domains in production
  allowMethods: ['GET', 'POST', 'DELETE', 'HEAD', 'OPTIONS'],
  allowHeaders: ['Content-Type', 'Authorization'],
}));

// Health check
app.get('/health', (c) => c.json({ status: 'ok' }));

// Mount routes
app.route('', schedules);  // Mount at root for /check-location
app.route('/api', schedules);  // Backward compat: /api/check-location
app.route('/subscriptions', subscriptions);

export default app;
