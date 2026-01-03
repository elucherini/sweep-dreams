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

const METERS_TO_FEET = 3.28084;
const FEET_PER_MILE = 5280;
const FEET_THRESHOLD = 1000; // Switch to miles above this

/**
 * Convert meters to a human-readable distance string in feet or miles.
 * Uses feet for distances under 1000 ft, miles for longer distances.
 */
function formatDistance(meters: number): string {
  const feet = meters * METERS_TO_FEET;

  if (feet < FEET_THRESHOLD) {
    return `${Math.round(feet)} ft`;
  }

  const miles = feet / FEET_PER_MILE;
  if (miles < 10) {
    return `${miles.toFixed(1)} mi`;
  }
  return `${Math.round(miles)} mi`;
}

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
 * Represents a block result.
 */
interface BlockResult {
  blockSweepId: number;
  corridor: string;
  limits: string;
  blockSide: string | null;
  cnnRightLeft: string;  // 'L' or 'R' - which side of the centerline this is
  humanRules: string[];
  nextSweepStart: Date;
  nextSweepEnd: Date;
  distanceMeters: number | undefined;
  isUserSide: boolean | undefined;
  geometry: any;  // GeoJSON LineString centerline for map visualization
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
      const blockResults: BlockResult[] = [];

      for (const [_, blockSchedules] of blocks) {
        try {
          const { start, end, blockSweepId } = findEarliestSweepWindow(blockSchedules, now);

          // Get human-readable rules
          const humanRules = blockSchedules.map(s => formatSchedule(s));

          // Use the minimum distance from all schedules in the block
          const distanceMeters = blockSchedules
            .map(s => s.distance_meters)
            .filter((d): d is number => d !== undefined)
            .reduce((min, d) => Math.min(min, d), Infinity);

          // Determine if user is on this side (true if any schedule in block has is_user_side=true)
          const isUserSide = blockSchedules.some(s => s.is_user_side === true)
            ? true
            : blockSchedules.every(s => s.is_user_side === false)
              ? false
              : undefined;

          blockResults.push({
            blockSweepId,
            corridor: blockSchedules[0].corridor,
            limits: blockSchedules[0].limits,
            blockSide: blockSchedules[0].block_side,
            cnnRightLeft: blockSchedules[0].cnn_right_left,
            humanRules,
            nextSweepStart: start,
            nextSweepEnd: end,
            distanceMeters: distanceMeters !== Infinity ? distanceMeters : undefined,
            isUserSide,
            geometry: blockSchedules[0].line_geojson,
          });
        } catch (error) {
          // Skip blocks that can't compute windows
          continue;
        }
      }

      // Format results for response
      const results = blockResults.map((r: BlockResult) => ({
        block_sweep_id: r.blockSweepId,
        corridor: r.corridor,
        limits: r.limits,
        block_side: r.blockSide,
        cnn_right_left: r.cnnRightLeft,
        human_rules: r.humanRules,
        next_sweep_start: r.nextSweepStart.toISOString(),
        next_sweep_end: r.nextSweepEnd.toISOString(),
        distance: r.distanceMeters !== undefined ? formatDistance(r.distanceMeters) : undefined,
        is_user_side: r.isUserSide,
        geometry: r.geometry,
      }));

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
