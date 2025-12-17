import { Hono } from 'hono';
import { z } from 'zod';
import { zValidator } from '@hono/zod-validator';
import { SupabaseClient } from '../supabase';
import { nextSweepWindow, formatPacificTime } from '../lib/calendar';

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

    const supabase = new SupabaseClient({
      url: c.env.SUPABASE_URL,
      key: c.env.SUPABASE_KEY,
    });

    // 1. Upsert subscription to database
    const record = await supabase.upsertSubscription({
      deviceToken: data.device_token,
      platform: data.platform,
      scheduleBlockSweepId: data.schedule_block_sweep_id,
      latitude: data.latitude,
      longitude: data.longitude,
      leadMinutes: data.lead_minutes,
    });

    // 2. Fetch the schedule to compute next sweep window
    let schedule;
    try {
      schedule = await supabase.getScheduleByBlockSweepId(
        record.schedule_block_sweep_id
      );
    } catch (error) {
      return c.json({ error: 'Schedule not found' }, 404);
    }

    // 3. Compute next sweep window
    const [start, end] = nextSweepWindow(schedule);

    // 4. Return response
    return c.json({
      device_token: record.device_token,
      platform: record.platform,
      schedule_block_sweep_id: record.schedule_block_sweep_id,
      lead_minutes: record.lead_minutes,
      next_sweep_start: formatPacificTime(start),
      next_sweep_end: formatPacificTime(end),
    }, 201);
  }
);

// GET /subscriptions/:device_token
subscriptions.get('/:device_token', async (c) => {
  const deviceToken = c.req.param('device_token');

  const supabase = new SupabaseClient({
    url: c.env.SUPABASE_URL,
    key: c.env.SUPABASE_KEY,
  });

  // 1. Fetch subscription
  const record = await supabase.getSubscriptionByDeviceToken(deviceToken);
  if (!record) {
    return c.json({ error: 'Subscription not found' }, 404);
  }

  // 2. Fetch schedule and compute next sweep
  let schedule;
  try {
    schedule = await supabase.getScheduleByBlockSweepId(
      record.schedule_block_sweep_id
    );
  } catch (error) {
    return c.json({ error: 'Schedule not found' }, 404);
  }

  const [start, end] = nextSweepWindow(schedule);

  // 3. Return response
  return c.json({
    device_token: record.device_token,
    platform: record.platform,
    schedule_block_sweep_id: record.schedule_block_sweep_id,
    lead_minutes: record.lead_minutes,
    next_sweep_start: formatPacificTime(start),
    next_sweep_end: formatPacificTime(end),
  });
});

// DELETE /subscriptions/:device_token
subscriptions.delete('/:device_token', async (c) => {
  const deviceToken = c.req.param('device_token');

  const supabase = new SupabaseClient({
    url: c.env.SUPABASE_URL,
    key: c.env.SUPABASE_KEY,
  });

  const deleted = await supabase.deleteSubscription(deviceToken);
  if (!deleted) {
    return c.json({ error: 'Subscription not found' }, 404);
  }

  return c.body(null, 204);
});

export default subscriptions;
