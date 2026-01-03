import { z } from 'zod';

// Enums
export enum Weekday {
  MON = 0,
  TUE = 1,
  WED = 2,
  THU = 3,
  FRI = 4,
  SAT = 5,
  SUN = 6,
}

export const WEEKDAY_LOOKUP: Record<string, Weekday> = {
  'mon': Weekday.MON,
  'monday': Weekday.MON,
  'tues': Weekday.TUE,
  'tue': Weekday.TUE,
  'tuesday': Weekday.TUE,
  'wed': Weekday.WED,
  'weds': Weekday.WED,
  'wednesday': Weekday.WED,
  'thu': Weekday.THU,
  'thur': Weekday.THU,
  'thurs': Weekday.THU,
  'thursday': Weekday.THU,
  'fri': Weekday.FRI,
  'friday': Weekday.FRI,
  'sat': Weekday.SAT,
  'saturday': Weekday.SAT,
  'sun': Weekday.SUN,
  'sunday': Weekday.SUN,
};

// Types
export type Coord = [number, number];  // [lon, lat]

// Schemas
export const BlockKeySchema = z.object({
  cnn: z.number(),
  corridor: z.string(),
  limits: z.string(),
  cnn_right_left: z.string(),
  block_side: z.string().nullable(),
});
export type BlockKey = z.infer<typeof BlockKeySchema>;

export const TimeWindowSchema = z.object({
  start: z.string().regex(/^\d{2}:\d{2}$/),  // "HH:MM" format
  end: z.string().regex(/^\d{2}:\d{2}$/),
});
export type TimeWindow = z.infer<typeof TimeWindowSchema>;

export const MonthlyPatternSchema = z.object({
  weekdays: z.array(z.nativeEnum(Weekday)),
  weeks_of_month: z.array(z.number().min(1).max(5)).nullable(),
});
export type MonthlyPattern = z.infer<typeof MonthlyPatternSchema>;

export const RecurringRuleSchema = z.object({
  pattern: MonthlyPatternSchema,
  time_window: TimeWindowSchema,
  skip_holidays: z.boolean().default(false),
});
export type RecurringRule = z.infer<typeof RecurringRuleSchema>;

// Custom transformer for line coordinates
const coordTransformer = z.preprocess((val) => {
  if (val === null || val === undefined) {
    return [];
  }

  // Handle GeoJSON format with coordinates property
  if (typeof val === 'object' && val !== null && 'coordinates' in val) {
    const coords = (val as any).coordinates;
    if (Array.isArray(coords)) {
      return coords
        .filter((coord: any) => Array.isArray(coord) && coord.length >= 2)
        .map((coord: any) => [Number(coord[0]), Number(coord[1])]);
    }
  }

  // Handle array of coordinates
  if (Array.isArray(val)) {
    return val
      .filter((coord: any) => Array.isArray(coord) && coord.length >= 2)
      .map((coord: any) => [Number(coord[0]), Number(coord[1])]);
  }

  // Handle WKT-like strings (e.g., "LINESTRING (lon lat, lon lat)")
  if (typeof val === 'string') {
    let text = val.trim();
    if (text.toUpperCase().startsWith('LINESTRING')) {
      text = text.slice(10).trim();
    }
    text = text.replace(/[()]/g, '');
    const coords: Coord[] = [];
    for (const pair of text.split(',')) {
      const parts = pair.trim().split(/\s+/);
      if (parts.length === 2) {
        const lon = Number(parts[0]);
        const lat = Number(parts[1]);
        if (!isNaN(lon) && !isNaN(lat)) {
          coords.push([lon, lat]);
        }
      }
    }
    return coords;
  }

  return val;
}, z.array(z.tuple([z.number(), z.number()])));

export const SweepingScheduleSchema = z.object({
  cnn: z.number(),
  corridor: z.string(),
  limits: z.string(),
  cnn_right_left: z.string(),
  block_side: z.string().nullable(),
  full_name: z.string(),
  week_day: z.string(),
  from_hour: z.number().int().min(0).max(23),
  to_hour: z.number().int().min(0).max(23),
  week1: z.boolean(),
  week2: z.boolean(),
  week3: z.boolean(),
  week4: z.boolean(),
  week5: z.boolean(),
  holidays: z.boolean(),
  block_sweep_id: z.number(),
  line: coordTransformer,
  distance_meters: z.number().optional(),
  is_user_side: z.boolean().optional(),
  line_geojson: z.any(),  // GeoJSON LineString for the centerline
});
export type SweepingSchedule = z.infer<typeof SweepingScheduleSchema>;

// Response models (for API)
export const CheckLocationResponseSchema = z.object({
  request_point: z.object({
    latitude: z.number(),
    longitude: z.number(),
  }),
  schedules: z.array(z.object({
    block_sweep_id: z.number(),
    corridor: z.string(),
    limits: z.string(),
    human_rules: z.array(z.string()),
    next_sweep_start: z.string(),  // ISO8601
    next_sweep_end: z.string(),    // ISO8601
    distance: z.string().optional(),  // Human-readable, e.g. "50 ft" or "0.3 mi"
    is_user_side: z.boolean().optional(),  // True if this is the side of the street the user is on
    geometry: z.any(),  // GeoJSON LineString centerline (for map visualization)
  })),
  timezone: z.string(),
});
export type CheckLocationResponse = z.infer<typeof CheckLocationResponseSchema>;

// Subscription record from database
export const SubscriptionRecordSchema = z.object({
  device_token: z.string(),
  platform: z.enum(['ios', 'android', 'web']),
  schedule_block_sweep_id: z.number(),
  lead_minutes: z.number(),
  last_notified_at: z.string().nullable().optional(),
});

export type SubscriptionRecord = z.infer<typeof SubscriptionRecordSchema>;
