import { Hono } from 'hono';
import { z } from 'zod';
import { zValidator } from '@hono/zod-validator';
import { SupabaseClient, SubscriptionLimitError } from '../../shared/supabase';
import { nextSweepWindow, nextMoveDeadline, formatPacificTime } from '../../shared/lib/calendar';
import { isTimingLimitedRegulation } from '../../shared/models/parking';

type Bindings = {
  SUPABASE_URL: string;
  SUPABASE_KEY: string;
};

const subscriptions = new Hono<{ Bindings: Bindings }>();

const subscribeSchema = z.object({
  device_token: z.string().min(1),
  platform: z.enum(['ios', 'android', 'web']),
  subscription_type: z.enum(['sweeping', 'timing']).default('sweeping'),
  schedule_block_sweep_id: z.number(),
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  lead_minutes: z.number().int().min(0),
}).superRefine((data, ctx) => {
  const lead = data.lead_minutes;
  if (data.subscription_type === 'timing') {
    if (lead % 15 !== 0) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['lead_minutes'],
        message: 'lead_minutes must be a multiple of 15 for timing subscriptions',
      });
    }
    return;
  }

  if (lead % 30 !== 0) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['lead_minutes'],
      message: 'lead_minutes must be a multiple of 30 for sweeping subscriptions',
    });
  }
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
    let record;
    try {
      record = await supabase.upsertSubscription({
        deviceToken: data.device_token,
        platform: data.platform,
        scheduleBlockSweepId: data.schedule_block_sweep_id,
        latitude: data.latitude,
        longitude: data.longitude,
        leadMinutes: data.lead_minutes,
        subscriptionType: data.subscription_type,
      });
    } catch (error) {
      if (error instanceof SubscriptionLimitError) {
        return c.json({ error: 'Maximum subscriptions limit reached' }, 409);
      }
      throw error;
    }

    // 2. Branch based on subscription type
    if (data.subscription_type === 'timing') {
      // Timing subscription: fetch parking regulation and compute move deadline
      let regulation;
      try {
        regulation = await supabase.getParkingRegulationById(
          record.schedule_block_sweep_id
        );
      } catch {
        return c.json({ error: 'Parking regulation not found' }, 404);
      }

      if (!isTimingLimitedRegulation(regulation)) {
        return c.json({ error: 'Parking regulation is not time-limited' }, 400);
      }

      // Validate required fields for timing calculation
      if (regulation.days === null || regulation.hrs_begin === null || regulation.hrs_end === null || regulation.hour_limit === null) {
        return c.json({ error: 'Parking regulation missing required fields for timing calculation' }, 400);
      }

      // Use created_at as the "parked at" time for computing the fixed deadline
      const parkedAt = new Date(record.created_at);
      const deadline = nextMoveDeadline(
        regulation.days,
        regulation.hrs_begin,
        regulation.hrs_end,
        regulation.hour_limit,
        parkedAt
      );

      return c.json({
        device_token: record.device_token,
        platform: record.platform,
        subscription_type: 'timing',
        schedule_block_sweep_id: record.schedule_block_sweep_id,
        lead_minutes: record.lead_minutes,
        regulation: regulation.regulation,
        hour_limit: regulation.hour_limit,
        days: regulation.days,
        from_time: regulation.from_time,
        to_time: regulation.to_time,
        next_move_deadline: formatPacificTime(deadline),
      }, 201);
    }

    // Sweeping subscription: fetch schedule and compute next sweep window
    let schedule;
    try {
      schedule = await supabase.getScheduleByBlockSweepId(
        record.schedule_block_sweep_id
      );
    } catch {
      return c.json({ error: 'Schedule not found' }, 404);
    }

    const [start, end] = nextSweepWindow(schedule);

    return c.json({
      device_token: record.device_token,
      platform: record.platform,
      subscription_type: 'sweeping',
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

  // 2. Fetch details and compute deadlines for each subscription based on type
  const subscriptionsWithDetails = await Promise.all(
    records.map(async (record) => {
      if (record.subscription_type === 'timing') {
        // Timing subscription: fetch parking regulation
        try {
          const regulation = await supabase.getParkingRegulationById(
            record.schedule_block_sweep_id
          );

          if (!isTimingLimitedRegulation(regulation)) {
            return {
              subscription_type: 'timing',
              schedule_block_sweep_id: record.schedule_block_sweep_id,
              lead_minutes: record.lead_minutes,
              last_notified_at: record.last_notified_at ?? null,
              regulation: regulation.regulation,
              hour_limit: regulation.hour_limit,
              days: regulation.days,
              from_time: regulation.from_time,
              to_time: regulation.to_time,
              next_move_deadline: null,
              error: 'Parking regulation is not time-limited',
            };
          }

          // Check required fields
          if (regulation.days === null || regulation.hrs_begin === null || regulation.hrs_end === null || regulation.hour_limit === null) {
            return {
              subscription_type: 'timing',
              schedule_block_sweep_id: record.schedule_block_sweep_id,
              lead_minutes: record.lead_minutes,
              last_notified_at: record.last_notified_at ?? null,
              regulation: regulation.regulation,
              hour_limit: regulation.hour_limit,
              days: regulation.days,
              from_time: regulation.from_time,
              to_time: regulation.to_time,
              next_move_deadline: null,
              error: 'Missing required fields for timing calculation',
            };
          }

          // Use created_at as the "parked at" time for computing the fixed deadline
          const parkedAt = new Date(record.created_at);
          const deadline = nextMoveDeadline(
            regulation.days,
            regulation.hrs_begin,
            regulation.hrs_end,
            regulation.hour_limit,
            parkedAt
          );

          return {
            subscription_type: 'timing',
            schedule_block_sweep_id: record.schedule_block_sweep_id,
            lead_minutes: record.lead_minutes,
            last_notified_at: record.last_notified_at ?? null,
            regulation: regulation.regulation,
            hour_limit: regulation.hour_limit,
            days: regulation.days,
            from_time: regulation.from_time,
            to_time: regulation.to_time,
            next_move_deadline: formatPacificTime(deadline),
          };
        } catch {
          return {
            subscription_type: 'timing',
            schedule_block_sweep_id: record.schedule_block_sweep_id,
            lead_minutes: record.lead_minutes,
            last_notified_at: record.last_notified_at ?? null,
            regulation: null,
            hour_limit: null,
            days: null,
            from_time: null,
            to_time: null,
            next_move_deadline: null,
            error: 'Parking regulation not found',
          };
        }
      }

      // Sweeping subscription: fetch schedule
      try {
        const schedule = await supabase.getScheduleByBlockSweepId(
          record.schedule_block_sweep_id
        );
        const [start, end] = nextSweepWindow(schedule);
        return {
          subscription_type: 'sweeping',
          schedule_block_sweep_id: record.schedule_block_sweep_id,
          lead_minutes: record.lead_minutes,
          last_notified_at: record.last_notified_at ?? null,
          corridor: schedule.corridor,
          limits: schedule.limits,
          block_side: schedule.block_side,
          next_sweep_start: formatPacificTime(start),
          next_sweep_end: formatPacificTime(end),
        };
      } catch {
        return {
          subscription_type: 'sweeping',
          schedule_block_sweep_id: record.schedule_block_sweep_id,
          lead_minutes: record.lead_minutes,
          last_notified_at: record.last_notified_at ?? null,
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
    subscriptions: subscriptionsWithDetails,
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

  // 2. Branch based on subscription type
  if (record.subscription_type === 'timing') {
    // Timing subscription: fetch parking regulation
    let regulation;
    try {
      regulation = await supabase.getParkingRegulationById(
        record.schedule_block_sweep_id
      );
    } catch {
      return c.json({ error: 'Parking regulation not found' }, 404);
    }

    if (!isTimingLimitedRegulation(regulation)) {
      return c.json({ error: 'Parking regulation is not time-limited' }, 400);
    }

    // Validate required fields
    if (regulation.days === null || regulation.hrs_begin === null || regulation.hrs_end === null || regulation.hour_limit === null) {
      return c.json({ error: 'Parking regulation missing required fields for timing calculation' }, 400);
    }

    // Use created_at as the "parked at" time for computing the fixed deadline
    const parkedAt = new Date(record.created_at);
    const deadline = nextMoveDeadline(
      regulation.days,
      regulation.hrs_begin,
      regulation.hrs_end,
      regulation.hour_limit,
      parkedAt
    );

    return c.json({
      device_token: record.device_token,
      platform: record.platform,
      subscription_type: 'timing',
      schedule_block_sweep_id: record.schedule_block_sweep_id,
      lead_minutes: record.lead_minutes,
      regulation: regulation.regulation,
      hour_limit: regulation.hour_limit,
      days: regulation.days,
      from_time: regulation.from_time,
      to_time: regulation.to_time,
      next_move_deadline: formatPacificTime(deadline),
    });
  }

  // Sweeping subscription: fetch schedule and compute next sweep
  let schedule;
  try {
    schedule = await supabase.getScheduleByBlockSweepId(
      record.schedule_block_sweep_id
    );
  } catch {
    return c.json({ error: 'Schedule not found' }, 404);
  }

  const [start, end] = nextSweepWindow(schedule);

  return c.json({
    device_token: record.device_token,
    platform: record.platform,
    subscription_type: 'sweeping',
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
