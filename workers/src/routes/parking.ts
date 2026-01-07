import { Hono } from 'hono';
import { z } from 'zod';
import { zValidator } from '@hono/zod-validator';
import { ParkingRegulationSchema, type ParkingRegulation } from '../models/parking';

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
  radiusMeters: number = 25,
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
        radius ?? 25,  // Default 25m radius
      );

      return c.json({
        request_point: { latitude, longitude },
        regulations: regulations.map(formatRegulation),
        timezone: 'America/Los_Angeles',
      }, 200);

    } catch (error) {
      console.error('Error fetching parking regulations:', error);
      return c.json({ error: 'Failed to fetch parking regulations' }, 502);
    }
  }
);

export default parking;
