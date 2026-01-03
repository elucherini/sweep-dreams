-- Migration: Add User Side Detection to schedules_near
-- This migration enhances the schedules_near function to indicate which side
-- of the street the user is closest to via a new is_user_side boolean field.

-- Drop the existing function first since we're changing the return type
DROP FUNCTION IF EXISTS public.schedules_near(double precision, double precision);

CREATE FUNCTION public.schedules_near(lon double precision, lat double precision)
RETURNS TABLE (
  cnn bigint,
  corridor text,
  limits text,
  cnn_right_left text,
  block_side text,
  full_name text,
  week_day text,
  from_hour smallint,
  to_hour smallint,
  week1 boolean,
  week2 boolean,
  week3 boolean,
  week4 boolean,
  week5 boolean,
  holidays boolean,
  block_sweep_id bigint,
  line extensions.geometry(LineString,4326),
  created_at timestamp without time zone,
  distance_meters double precision,

  -- New field
  is_user_side boolean
)
LANGUAGE sql STABLE
AS $$
WITH params AS (
  SELECT
    extensions.ST_SetSRID(extensions.ST_Point(lon, lat), 4326) AS p,
    0.001::double precision AS max_deg_dist   -- ~100m
),

-- Find all schedules within radius, compute distance once
candidates AS (
  SELECT
    s.*,
    params.p,
    extensions.ST_Distance(s.line, params.p) AS dist_deg,
    extensions.ST_Distance(s.line::extensions.geography, params.p::extensions.geography) AS distance_meters
  FROM public.schedules s, params
  WHERE extensions.ST_Distance(s.line, params.p) <= params.max_deg_dist
),

-- Transform to meters using UTM Zone 10N (SRID 32610) for accurate offset calculations
-- UTM 32610 covers SF with minimal distortion, unlike Web Mercator (3857) which has ~20% error
with_metrics AS (
  SELECT
    c.*,
    extensions.ST_Transform(c.line, 32610) AS line_m,
    extensions.ST_Transform(c.p, 32610) AS p_m
  FROM candidates c
),

-- Compute distance from user to each side's offset line
-- PostGIS convention: positive offset = left, negative = right
-- Use 10m offset to handle varying street widths (residential ~12m, arterials ~25m)
-- A larger offset is conservative - ensures we don't misclassify on wide streets
with_side_distances AS (
  SELECT
    wm.*,
    COALESCE(
      extensions.ST_Distance(wm.p_m, extensions.ST_OffsetCurve(wm.line_m, 10.0)),
      extensions.ST_Distance(wm.p_m, wm.line_m)
    ) AS dist_to_left_m,
    COALESCE(
      extensions.ST_Distance(wm.p_m, extensions.ST_OffsetCurve(wm.line_m, -10.0)),
      extensions.ST_Distance(wm.p_m, wm.line_m)
    ) AS dist_to_right_m
  FROM with_metrics wm
)

-- Return all records with is_user_side flag
-- No window function needed: all records for a block share the same geometry,
-- so dist_to_left_m and dist_to_right_m are identical within each block
SELECT
  wsd.cnn,
  wsd.corridor,
  wsd.limits,
  wsd.cnn_right_left,
  wsd.block_side,
  wsd.full_name,
  wsd.week_day,
  wsd.from_hour,
  wsd.to_hour,
  wsd.week1,
  wsd.week2,
  wsd.week3,
  wsd.week4,
  wsd.week5,
  wsd.holidays,
  wsd.block_sweep_id,
  wsd.line,
  wsd.created_at,
  wsd.distance_meters,

  -- TRUE if this record's side matches the side the user is closest to
  (CASE WHEN wsd.dist_to_left_m <= wsd.dist_to_right_m THEN 'L' ELSE 'R' END = wsd.cnn_right_left) AS is_user_side
FROM with_side_distances wsd
ORDER BY wsd.dist_deg;
$$;
