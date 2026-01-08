import { z } from 'zod';

/**
 * Parking regulation record from the database.
 * Represents SF parking regulations (time limits, RPP zones, etc.)
 */
export const ParkingRegulationSchema = z.object({
  id: z.number(),
  regulation: z.string(),
  days: z.string().nullable(),
  hrs_begin: z.number().nullable(),  // Military time: 900 = 9:00 AM
  hrs_end: z.number().nullable(),    // Military time: 1800 = 6:00 PM
  hour_limit: z.number().nullable(), // e.g., 2 for "2-hour parking"
  rpp_area1: z.string().nullable(),  // RPP zone: 'N', 'L', 'K', etc.
  rpp_area2: z.string().nullable(),
  exceptions: z.string().nullable(), // "Yes. RPP holders are exempt..."
  from_time: z.string().nullable(),  // Human-readable: "9am"
  to_time: z.string().nullable(),    // Human-readable: "6pm"
  neighborhood: z.string().nullable(),
  line: z.any(),  // PostGIS geometry (MultiLineString)
  distance_meters: z.number().optional(),  // Only present in spatial queries
});

export type ParkingRegulation = z.infer<typeof ParkingRegulationSchema>;
