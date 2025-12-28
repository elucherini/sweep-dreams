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
 * Represents a block result, potentially merged from two sides with identical schedules.
 */
interface BlockResult {
  blockSweepId: number;
  corridor: string;
  limits: string;
  blockSide: string | null;
  humanRules: string[];
  nextSweepStart: Date;
  nextSweepEnd: Date;
  distanceMeters: number | undefined;
}

/**
 * Check if two block results have identical schedules (same corridor, limits, and sweep times).
 */
function areBlocksIdentical(a: BlockResult, b: BlockResult): boolean {
  return (
    a.corridor === b.corridor &&
    a.limits === b.limits &&
    a.nextSweepStart.getTime() === b.nextSweepStart.getTime() &&
    a.nextSweepEnd.getTime() === b.nextSweepEnd.getTime()
  );
}

/**
 * Check if two block sides are opposites (e.g., East/West, North/South).
 */
function areOppositeSides(sideA: string | null, sideB: string | null): boolean {
  if (!sideA || !sideB) return false;

  const opposites: Record<string, string> = {
    East: 'West',
    West: 'East',
    North: 'South',
    South: 'North',
    NorthEast: 'SouthWest',
    SouthWest: 'NorthEast',
    NorthWest: 'SouthEast',
    SouthEast: 'NorthWest',
  };

  return opposites[sideA] === sideB;
}

/**
 * Merge block results that have identical schedules on opposite sides of the same block.
 * Returns merged results with blockSide set to null for merged entries.
 */
function mergeIdenticalOppositeSides(results: BlockResult[]): BlockResult[] {
  const merged: BlockResult[] = [];
  const used = new Set<number>();

  for (let i = 0; i < results.length; i++) {
    if (used.has(i)) continue;

    const current = results[i];
    let wasMerged = false;

    // Look for a matching opposite side
    for (let j = i + 1; j < results.length; j++) {
      if (used.has(j)) continue;

      const candidate = results[j];

      if (
        areBlocksIdentical(current, candidate) &&
        areOppositeSides(current.blockSide, candidate.blockSide)
      ) {
        // Merge: use first one's data but set blockSide to null
        merged.push({
          ...current,
          blockSide: null,
        });
        used.add(i);
        used.add(j);
        wasMerged = true;
        break;
      }
    }

    if (!wasMerged) {
      merged.push(current);
      used.add(i);
    }
  }

  return merged;
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

          blockResults.push({
            blockSweepId,
            corridor: blockSchedules[0].corridor,
            limits: blockSchedules[0].limits,
            blockSide: blockSchedules[0].block_side,
            humanRules,
            nextSweepStart: start,
            nextSweepEnd: end,
            distanceMeters: distanceMeters !== Infinity ? distanceMeters : undefined,
          });
        } catch (error) {
          // Skip blocks that can't compute windows
          continue;
        }
      }

      // Merge blocks that have identical schedules on opposite sides
      const mergedResults = mergeIdenticalOppositeSides(blockResults);

      // Format results for response
      const results = mergedResults.map(r => ({
        block_sweep_id: r.blockSweepId,
        corridor: r.corridor,
        limits: r.limits,
        block_side: r.blockSide,
        human_rules: r.humanRules,
        next_sweep_start: r.nextSweepStart.toISOString(),
        next_sweep_end: r.nextSweepEnd.toISOString(),
        distance: r.distanceMeters !== undefined ? formatDistance(r.distanceMeters) : undefined,
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
