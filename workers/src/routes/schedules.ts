import { Hono } from 'hono';
import { z } from 'zod';
import { zValidator } from '@hono/zod-validator';
import { SupabaseClient } from '../supabase';
import { nextSweepWindow } from '../lib/calendar';
import { formatSchedule } from '../lib/formatting';
import type { SweepingSchedule } from '../models';

type Bindings = {
  SUPABASE_URL: string;
  SUPABASE_KEY: string;
};

const schedules = new Hono<{ Bindings: Bindings }>();

const locationSchema = z.object({
  latitude: z.coerce.number().min(-90).max(90),
  longitude: z.coerce.number().min(-180).max(180),
});

/**
 * Group schedules by block (same cnn + corridor + limits + side).
 */
function groupSchedulesByBlock(schedules: SweepingSchedule[]): Map<string, SweepingSchedule[]> {
  const groups = new Map<string, SweepingSchedule[]>();

  for (const schedule of schedules) {
    const key = [
      schedule.cnn,
      schedule.corridor,
      schedule.limits,
      schedule.cnn_right_left,
      schedule.block_side || 'null',
    ].join('|');

    if (!groups.has(key)) {
      groups.set(key, []);
    }
    groups.get(key)!.push(schedule);
  }

  return groups;
}

/**
 * Find the earliest next sweep window across all schedules in a block.
 */
function findEarliestSweepWindow(
  schedules: SweepingSchedule[],
  now: Date,
): { start: Date; end: Date; blockSweepId: number } {
  let earliestStart: Date | null = null;
  let earliestEnd: Date | null = null;
  let earliestBlockSweepId: number | null = null;

  for (const schedule of schedules) {
    try {
      const [start, end] = nextSweepWindow(schedule, now);

      if (earliestStart === null || start < earliestStart) {
        earliestStart = start;
        earliestEnd = end;
        earliestBlockSweepId = schedule.block_sweep_id;
      }
    } catch (error) {
      // Skip schedules that can't compute windows (e.g., holiday-only)
      continue;
    }
  }

  if (earliestStart === null || earliestEnd === null || earliestBlockSweepId === null) {
    throw new Error('Could not compute sweep window for block');
  }

  return { start: earliestStart, end: earliestEnd, blockSweepId: earliestBlockSweepId };
}

schedules.get(
  '/check-location',
  zValidator('query', locationSchema),
  async (c) => {
    const { latitude, longitude } = c.req.valid('query');

    const supabase = new SupabaseClient({
      url: c.env.SUPABASE_URL,
      key: c.env.SUPABASE_KEY,
    });

    try {
      // Fetch nearby schedules from Supabase
      const rawSchedules = await supabase.closestSchedules(latitude, longitude);

      if (rawSchedules.length === 0) {
        return c.json({
          request_point: { latitude, longitude },
          schedules: [],
          timezone: 'America/Los_Angeles',
        });
      }

      // Group by block and compute next sweep window for each
      const blocks = groupSchedulesByBlock(rawSchedules);
      const now = new Date();
      const results = [];

      for (const [_, blockSchedules] of blocks) {
        try {
          const { start, end, blockSweepId } = findEarliestSweepWindow(blockSchedules, now);

          // Get human-readable rules
          const humanRules = blockSchedules.map(s => formatSchedule(s));

          results.push({
            block_sweep_id: blockSweepId,
            corridor: blockSchedules[0].corridor,
            limits: blockSchedules[0].limits,
            human_rules: humanRules,
            next_sweep_start: start.toISOString(),
            next_sweep_end: end.toISOString(),
          });
        } catch (error) {
          // Skip blocks that can't compute windows
          continue;
        }
      }

      return c.json({
        request_point: { latitude, longitude },
        schedules: results,
        timezone: 'America/Los_Angeles',
      }, 200);

    } catch (error) {
      console.error('Error fetching schedules:', error);
      return c.json({ error: 'Failed to fetch schedules' }, 502);
    }
  }
);

export default schedules;
