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
      corridor: schedule.corridor,
      limits: schedule.limits,
      block_side: schedule.block_side,
      next_sweep_start: formatPacificTime(start),
      next_sweep_end: formatPacificTime(end),
    }, 201);
  }
);

// GET /subscriptions/:device_token - Get all subscriptions for a device
subscriptions.get('/:device_token', async (c) => {
  const deviceToken = c.req.param('device_token');

  const supabase = new SupabaseClient({
    url: c.env.SUPABASE_URL,
    key: c.env.SUPABASE_KEY,
  });

  // 1. Fetch all subscriptions for this device
  const records = await supabase.getSubscriptionsByDeviceToken(deviceToken);
  if (records.length === 0) {
    return c.json({ error: 'No subscriptions found' }, 404);
  }

  // 2. Fetch schedules and compute next sweep for each subscription
  const subscriptionsWithSchedules = await Promise.all(
    records.map(async (record) => {
      try {
        const schedule = await supabase.getScheduleByBlockSweepId(
          record.schedule_block_sweep_id
        );
        const [start, end] = nextSweepWindow(schedule);
        return {
          schedule_block_sweep_id: record.schedule_block_sweep_id,
          lead_minutes: record.lead_minutes,
          corridor: schedule.corridor,
          limits: schedule.limits,
          block_side: schedule.block_side,
          next_sweep_start: formatPacificTime(start),
          next_sweep_end: formatPacificTime(end),
        };
      } catch {
        // Schedule not found - return subscription without schedule details
        return {
          schedule_block_sweep_id: record.schedule_block_sweep_id,
          lead_minutes: record.lead_minutes,
          corridor: null,
          limits: null,
          block_side: null,
          next_sweep_start: null,
          next_sweep_end: null,
          error: 'Schedule not found',
        };
      }
    })
  );

  // 3. Return response with array of subscriptions
  return c.json({
    device_token: deviceToken,
    platform: records[0].platform,
    subscriptions: subscriptionsWithSchedules,
  });
});

// GET /subscriptions/:device_token/:schedule_block_sweep_id - Get specific subscription
subscriptions.get('/:device_token/:schedule_block_sweep_id', async (c) => {
  const deviceToken = c.req.param('device_token');
  const scheduleBlockSweepId = parseInt(c.req.param('schedule_block_sweep_id'), 10);

  if (isNaN(scheduleBlockSweepId)) {
    return c.json({ error: 'Invalid schedule_block_sweep_id' }, 400);
  }

  const supabase = new SupabaseClient({
    url: c.env.SUPABASE_URL,
    key: c.env.SUPABASE_KEY,
  });

  // 1. Fetch specific subscription
  const record = await supabase.getSubscription(deviceToken, scheduleBlockSweepId);
  if (!record) {
    return c.json({ error: 'Subscription not found' }, 404);
  }

  // 2. Fetch schedule and compute next sweep
  let schedule;
  try {
    schedule = await supabase.getScheduleByBlockSweepId(
      record.schedule_block_sweep_id
    );
  } catch {
    return c.json({ error: 'Schedule not found' }, 404);
  }

  const [start, end] = nextSweepWindow(schedule);

  // 3. Return response
  return c.json({
    device_token: record.device_token,
    platform: record.platform,
    schedule_block_sweep_id: record.schedule_block_sweep_id,
    lead_minutes: record.lead_minutes,
    corridor: schedule.corridor,
    limits: schedule.limits,
    block_side: schedule.block_side,
    next_sweep_start: formatPacificTime(start),
    next_sweep_end: formatPacificTime(end),
  });
});

// DELETE /subscriptions/:device_token - Delete all subscriptions for a device
subscriptions.delete('/:device_token', async (c) => {
  const deviceToken = c.req.param('device_token');

  const supabase = new SupabaseClient({
    url: c.env.SUPABASE_URL,
    key: c.env.SUPABASE_KEY,
  });

  const deletedCount = await supabase.deleteAllSubscriptions(deviceToken);
  if (deletedCount === 0) {
    return c.json({ error: 'No subscriptions found' }, 404);
  }

  return c.body(null, 204);
});

// DELETE /subscriptions/:device_token/:schedule_block_sweep_id - Delete specific subscription
subscriptions.delete('/:device_token/:schedule_block_sweep_id', async (c) => {
  const deviceToken = c.req.param('device_token');
  const scheduleBlockSweepId = parseInt(c.req.param('schedule_block_sweep_id'), 10);

  if (isNaN(scheduleBlockSweepId)) {
    return c.json({ error: 'Invalid schedule_block_sweep_id' }, 400);
  }

  const supabase = new SupabaseClient({
    url: c.env.SUPABASE_URL,
    key: c.env.SUPABASE_KEY,
  });

  const deleted = await supabase.deleteSubscription(deviceToken, scheduleBlockSweepId);
  if (!deleted) {
    return c.json({ error: 'Subscription not found' }, 404);
  }

  return c.body(null, 204);
});

export default subscriptions;
