import { Hono } from 'hono';
import { z } from 'zod';
import { zValidator } from '@hono/zod-validator';
import { ParkingRegulationSchema, type ParkingRegulation } from '../models/parking';
import { nextMoveDeadline, formatPacificTime } from '../lib/calendar';

type Bindings = {
  SUPABASE_URL: string;
  SUPABASE_KEY: string;
};

const parking = new Hono<{ Bindings: Bindings }>();

const locationSchema = z.object({
  latitude: z.coerce.number().min(-90).max(90),
  longitude: z.coerce.number().min(-180).max(180),
  radius: z.coerce.number().min(1).max(500).optional(),  // Optional radius in meters
});

const METERS_TO_FEET = 3.28084;
const FEET_PER_MILE = 5280;
const FEET_THRESHOLD = 1000;

/**
 * Convert meters to a human-readable distance string in feet or miles.
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
 * Call the parking_regulations_near RPC function.
 */
async function fetchNearbyRegulations(
  supabaseUrl: string,
  supabaseKey: string,
  latitude: number,
  longitude: number,
  radiusMeters: number = 100,
): Promise<ParkingRegulation[]> {
  const rpcUrl = `${supabaseUrl}/rest/v1/rpc/parking_regulations_near`;

  const response = await fetch(rpcUrl, {
    method: 'POST',
    headers: {
      'apikey': supabaseKey,
      'Authorization': `Bearer ${supabaseKey}`,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    body: JSON.stringify({
      lon: longitude,
      lat: latitude,
      radius_meters: radiusMeters,
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

  return data.map((item: unknown) => ParkingRegulationSchema.parse(item));
}

/**
 * Compute the next move deadline ISO string for a parking regulation.
 * Returns null if the regulation doesn't have enough info to compute a deadline.
 */
function computeMoveDeadlineIso(reg: ParkingRegulation): string | null {
  // Need days, time range, and hour limit to compute deadline
  if (!reg.days || reg.hrs_begin == null || reg.hrs_end == null || !reg.hour_limit) {
    return null;
  }

  try {
    const deadline = nextMoveDeadline(reg.days, reg.hrs_begin, reg.hrs_end, reg.hour_limit);
    return formatPacificTime(deadline);
  } catch {
    // If parsing fails (unknown days pattern, etc.), return null
    return null;
  }
}

/**
 * Create a merge key for grouping regulations with identical schedules.
 */
function getMergeKey(reg: ParkingRegulation): string {
  const rppArea = reg.rpp_area1 || reg.rpp_area2 || '';
  return `${reg.regulation}|${reg.days ?? ''}|${reg.hrs_begin ?? ''}|${reg.hrs_end ?? ''}|${rppArea}`;
}

/**
 * Merge regulations with identical schedules (same regulation, days, hrs_begin, hrs_end).
 * Combines their geometries and uses the minimum distance.
 */
function mergeRegulations(regulations: ParkingRegulation[]): ParkingRegulation[] {
  const groups = new Map<string, ParkingRegulation[]>();

  // Group by merge key
  for (const reg of regulations) {
    const key = getMergeKey(reg);
    const group = groups.get(key);
    if (group) {
      group.push(reg);
    } else {
      groups.set(key, [reg]);
    }
  }

  // Merge each group
  const merged: ParkingRegulation[] = [];
  for (const group of groups.values()) {
    if (group.length === 1) {
      merged.push(group[0]);
      continue;
    }

    // Find the regulation with minimum distance (use as base)
    const base = group.reduce((min, reg) =>
      (reg.distance_meters ?? Infinity) < (min.distance_meters ?? Infinity) ? reg : min
    );

    // Combine all line geometries into one MultiLineString
    const allCoordinates: number[][][] = [];
    for (const reg of group) {
      if (reg.line?.type === 'MultiLineString' && Array.isArray(reg.line.coordinates)) {
        allCoordinates.push(...reg.line.coordinates);
      }
    }

    merged.push({
      ...base,
      line: allCoordinates.length > 0
        ? { type: 'MultiLineString', coordinates: allCoordinates }
        : base.line,
    });
  }

  return merged;
}

/**
 * Format a parking regulation for API response.
 */
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
    line: reg.line,  // MultiLineString geometry for map drawing
    next_move_deadline_iso: computeMoveDeadlineIso(reg),
  };
}

parking.get(
  '/check-parking',
  zValidator('query', locationSchema),
  async (c) => {
    const { latitude, longitude, radius } = c.req.valid('query');

    try {
      const regulations = await fetchNearbyRegulations(
        c.env.SUPABASE_URL,
        c.env.SUPABASE_KEY,
        latitude,
        longitude,
        radius ?? 150,  // Default 250m radius
      );

      const merged = mergeRegulations(regulations);

      return c.json({
        request_point: { latitude, longitude },
        regulations: merged.map(formatRegulation),
        timezone: 'America/Los_Angeles',
      }, 200);

    } catch (error) {
      console.error('Error fetching parking regulations:', error);
      return c.json({ error: 'Failed to fetch parking regulations' }, 502);
    }
  }
);

export default parking;
