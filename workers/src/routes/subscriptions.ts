import { Hono } from 'hono';
import { z } from 'zod';
import { zValidator } from '@hono/zod-validator';

type Bindings = {
  SUPABASE_URL: string;
  SUPABASE_KEY: string;
};

const subscriptions = new Hono<{ Bindings: Bindings }>();

const subscribeSchema = z.object({
  device_token: z.string().min(1),
  platform: z.enum(['ios', 'android', 'web']),
  schedule_block_sweep_id: z.number(),
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  lead_minutes: z.number().min(0).multipleOf(15),
});

// POST /subscriptions
subscriptions.post(
  '/',
  zValidator('json', subscribeSchema),
  async (c) => {
    const data = c.req.valid('json');

    // TODO: Implement subscription creation
    // 1. Fetch schedule by block_sweep_id
    // 2. Compute next sweep window
    // 3. Upsert to subscriptions table

    return c.json({
      device_token: data.device_token,
      schedule_block_sweep_id: data.schedule_block_sweep_id,
      next_sweep_start: new Date().toISOString(),
      next_sweep_end: new Date().toISOString(),
    }, 201);
  }
);

// GET /subscriptions/:device_token
subscriptions.get('/:device_token', async (c) => {
  const deviceToken = c.req.param('device_token');

  // TODO: Fetch from subscriptions table

  return c.json({
    device_token: deviceToken,
    schedule_block_sweep_id: 12345,
    next_sweep_start: new Date().toISOString(),
    next_sweep_end: new Date().toISOString(),
  });
});

// DELETE /subscriptions/:device_token
subscriptions.delete('/:device_token', async (c) => {
  const deviceToken = c.req.param('device_token');

  // TODO: Delete from subscriptions table

  return c.body(null, 204);
});

export default subscriptions;
