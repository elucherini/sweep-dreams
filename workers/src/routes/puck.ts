import { Hono } from 'hono';
import { z } from 'zod';
import { zValidator } from '@hono/zod-validator';
import { SupabaseClient } from '../../shared/supabase';
import { formatPacificTime, nextMoveDeadline, nextSweepWindow } from '../../shared/lib/calendar';
import { formatSchedule } from '../../shared/lib/formatting';
import type { ParkingRegulation } from '../../shared/models/parking';
import { isTimingLimitedRegulation, ParkingRegulationSchema } from '../../shared/models/parking';
import type { SweepingSchedule } from '../../shared/models';

type Bindings = {
  SUPABASE_URL: string;
  SUPABASE_KEY: string;
};

const puck = new Hono<{ Bindings: Bindings }>();

const puckSchema = z.object({
  latitude: z.coerce.number().min(-90).max(90),
  longitude: z.coerce.number().min(-180).max(180),
  radius: z.coerce.number().min(1).max(500).optional(),
});

const METERS_TO_FEET = 3.28084;
const FEET_PER_MILE = 5280;
const FEET_THRESHOLD = 1000;

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

async function fetchNearestRegulation(params: {
  supabaseUrl: string;
  supabaseKey: string;
  latitude: number;
  longitude: number;
  radiusMeters: number;
}): Promise<ParkingRegulation | null> {
  const rpcUrl = `${params.supabaseUrl}/rest/v1/rpc/parking_regulation_nearest`;

  const response = await fetch(rpcUrl, {
    method: 'POST',
    headers: {
      'apikey': params.supabaseKey,
      'Authorization': `Bearer ${params.supabaseKey}`,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    body: JSON.stringify({
      lon: params.longitude,
      lat: params.latitude,
      radius_meters: params.radiusMeters,
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Supabase RPC error ${response.status}: ${text}`);
  }

  const data = await response.json();

  if (!Array.isArray(data)) {
    throw new Error('Supabase RPC did not return an array');
  }

  if (data.length === 0) return null;
  const regulation = ParkingRegulationSchema.parse(data[0]);
  return isTimingLimitedRegulation(regulation) ? regulation : null;
}

function computeMoveDeadlineIso(reg: ParkingRegulation): string | null {
  if (!reg.days || reg.hrs_begin == null || reg.hrs_end == null || !reg.hour_limit) {
    return null;
  }

  try {
    const deadline = nextMoveDeadline(reg.days, reg.hrs_begin, reg.hrs_end, reg.hour_limit);
    return formatPacificTime(deadline);
  } catch {
    return null;
  }
}

function formatRegulation(reg: ParkingRegulation) {
  return {
    id: reg.id,
    regulation: reg.regulation,
    hour_limit: reg.hour_limit,
    days: reg.days,
    from_time: reg.from_time,
    to_time: reg.to_time,
    rpp_area: reg.rpp_area1 || reg.rpp_area2 || null,
    exceptions: reg.exceptions,
    neighborhood: reg.neighborhood,
    distance: formatDistance(reg.distance_meters ?? 0),
    distance_meters: reg.distance_meters ?? 0,
    line: reg.line,
    next_move_deadline_iso: computeMoveDeadlineIso(reg),
  };
}

type SideResult = {
  blockSweepId: number;
  corridor: string;
  limits: string;
  blockSide: string | null;
  cnnRightLeft: string;
  humanRules: string[];
  nextSweepStart: Date;
  nextSweepEnd: Date;
  distanceMeters: number | undefined;
  isUserSide: boolean;
  geometry: any;
};

function groupSchedulesBySide(schedules: SweepingSchedule[]): Map<string, SweepingSchedule[]> {
  const groups = new Map<string, SweepingSchedule[]>();
  for (const schedule of schedules) {
    const key = [
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
    } catch {
      continue;
    }
  }

  if (earliestStart === null || earliestEnd === null || earliestBlockSweepId === null) {
    throw new Error('Could not compute sweep window for side');
  }

  return { start: earliestStart, end: earliestEnd, blockSweepId: earliestBlockSweepId };
}

function formatScheduleSide(result: SideResult) {
  return {
    block_sweep_id: result.blockSweepId,
    corridor: result.corridor,
    limits: result.limits,
    block_side: result.blockSide,
    cnn_right_left: result.cnnRightLeft,
    human_rules: result.humanRules,
    next_sweep_start: formatPacificTime(result.nextSweepStart),
    next_sweep_end: formatPacificTime(result.nextSweepEnd),
    distance: result.distanceMeters !== undefined ? formatDistance(result.distanceMeters) : undefined,
    distance_meters: result.distanceMeters,
    is_user_side: result.isUserSide,
    geometry: result.geometry,
  };
}

puck.get(
  '/check-puck',
  zValidator('query', puckSchema),
  async (c) => {
    c.header('Cache-Control', 'public, max-age=10, stale-while-revalidate=60');

    const { latitude, longitude, radius } = c.req.valid('query');

    const scheduleClient = new SupabaseClient({
      url: c.env.SUPABASE_URL,
      key: c.env.SUPABASE_KEY,
      rpcFunction: 'schedules_near_closest_block',
    });

    let scheduleError: string | null = null;
    let parkingError: string | null = null;

    const schedulesPromise: Promise<SweepingSchedule[] | null> = (async () => {
      try {
        return await scheduleClient.closestSchedules(latitude, longitude);
      } catch (e) {
        scheduleError = e instanceof Error ? e.message : String(e);
        return null;
      }
    })();

    const regulationPromise: Promise<ParkingRegulation | null> = (async () => {
      try {
        return await fetchNearestRegulation({
          supabaseUrl: c.env.SUPABASE_URL,
          supabaseKey: c.env.SUPABASE_KEY,
          latitude,
          longitude,
          radiusMeters: radius ?? 150,
        });
      } catch (e) {
        parkingError = e instanceof Error ? e.message : String(e);
        return null;
      }
    })();

    const [schedules, regulation] = await Promise.all([schedulesPromise, regulationPromise]);

    const timezone = 'America/Los_Angeles';

    let schedulePayload: ReturnType<typeof formatScheduleSide> | null = null;
    if (schedules && schedules.length > 0) {
      const now = new Date();
      const groups = groupSchedulesBySide(schedules);
      const results: SideResult[] = [];

      for (const sideSchedules of groups.values()) {
        try {
          const { start, end, blockSweepId } = findEarliestSweepWindow(sideSchedules, now);
          const distanceMeters = sideSchedules
            .map(s => s.distance_meters)
            .filter((d): d is number => d !== undefined)
            .reduce((min, d) => Math.min(min, d), Infinity);

          results.push({
            blockSweepId,
            corridor: sideSchedules[0].corridor,
            limits: sideSchedules[0].limits,
            blockSide: sideSchedules[0].block_side,
            cnnRightLeft: sideSchedules[0].cnn_right_left,
            humanRules: sideSchedules.map(s => formatSchedule(s)),
            nextSweepStart: start,
            nextSweepEnd: end,
            distanceMeters: distanceMeters !== Infinity ? distanceMeters : undefined,
            isUserSide: sideSchedules.some(s => s.is_user_side === true),
            geometry: sideSchedules[0].line_geojson,
          });
        } catch {
          continue;
        }
      }

      results.sort(
        (a, b) => (a.distanceMeters ?? Infinity) - (b.distanceMeters ?? Infinity),
      );
      const chosen = results.find(r => r.isUserSide) ?? results[0] ?? null;
      schedulePayload = chosen ? formatScheduleSide(chosen) : null;
    }

    const response = {
      request_point: { latitude, longitude },
      schedule: schedulePayload,
      regulation: regulation ? formatRegulation(regulation) : null,
      timezone,
      errors: (scheduleError || parkingError)
        ? {
            schedule: scheduleError,
            regulation: parkingError,
          }
        : undefined,
    };

    return c.json(response, 200);
  },
);

export default puck;
