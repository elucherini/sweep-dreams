import { Hono } from 'hono';
import { cors } from 'hono/cors';
import subscriptions from './routes/subscriptions';
import puck from './routes/puck';

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
app.route('/api', puck);
app.route('/subscriptions', subscriptions);

export default app;
