-- Return side-aware distance for sweeping schedules.
--
-- Motivation:
-- - Sweeping schedule lines are placed at the center of the road.
-- - Parking regulation lines are placed at the curb (one line per side).
-- - To make distance_meters semantically consistent, schedules should return
--   the distance to the user's side (offset line) rather than the center line.
-- - This makes both data sources report "distance from the curb/line where the
--   regulation applies" for equivalent behavior in the API.

-- 1) schedules_near: return distance to user's side
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
  is_user_side boolean,
  line_geojson jsonb
)
LANGUAGE sql
STABLE
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
    extensions.ST_Distance(s.line::extensions.geography, params.p::extensions.geography) AS distance_meters_center
  FROM public.schedules s, params
  WHERE extensions.ST_DWithin(s.line, params.p, params.max_deg_dist)
),

-- Transform to meters using UTM Zone 10N (SRID 32610) for accurate offset calculations
with_metrics AS (
  SELECT
    c.*,
    extensions.ST_Transform(c.line, 32610) AS line_m,
    extensions.ST_Transform(c.p, 32610) AS p_m
  FROM candidates c
),

-- Compute distance from user to each side's offset line
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
  -- Return distance to the user's side (whichever is closer)
  LEAST(wsd.dist_to_left_m, wsd.dist_to_right_m) AS distance_meters,
  (CASE WHEN wsd.dist_to_left_m <= wsd.dist_to_right_m THEN 'L' ELSE 'R' END = wsd.cnn_right_left) AS is_user_side,
  extensions.ST_AsGeoJSON(wsd.line)::jsonb AS line_geojson
FROM with_side_distances wsd
ORDER BY wsd.dist_deg;
$$;

GRANT EXECUTE ON FUNCTION public.schedules_near(double precision, double precision) TO anon;
GRANT EXECUTE ON FUNCTION public.schedules_near(double precision, double precision) TO authenticated;
GRANT EXECUTE ON FUNCTION public.schedules_near(double precision, double precision) TO service_role;

-- 2) schedules_near_closest_block: return distance to user's side
DROP FUNCTION IF EXISTS public.schedules_near_closest_block(double precision, double precision);

CREATE FUNCTION public.schedules_near_closest_block(lon double precision, lat double precision)
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
  is_user_side boolean,
  line_geojson jsonb
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
    extensions.ST_Distance(s.line::extensions.geography, params.p::extensions.geography) AS distance_meters_center
  FROM public.schedules s, params
  WHERE extensions.ST_DWithin(s.line, params.p, params.max_deg_dist)
),

-- Transform to meters using UTM Zone 10N (SRID 32610) for accurate offset calculations
with_metrics AS (
  SELECT
    c.*,
    extensions.ST_Transform(c.line, 32610) AS line_m,
    extensions.ST_Transform(c.p, 32610) AS p_m
  FROM candidates c
),

-- Compute distance from user to each side's offset line
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
),

closest_block AS (
  SELECT cnn, corridor, limits
  FROM with_side_distances
  ORDER BY dist_deg
  LIMIT 1
)

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
  -- Return distance to the user's side (whichever is closer)
  LEAST(wsd.dist_to_left_m, wsd.dist_to_right_m) AS distance_meters,
  (CASE WHEN wsd.dist_to_left_m <= wsd.dist_to_right_m THEN 'L' ELSE 'R' END = wsd.cnn_right_left) AS is_user_side,
  extensions.ST_AsGeoJSON(wsd.line)::jsonb AS line_geojson
FROM with_side_distances wsd
JOIN closest_block cb
  ON wsd.cnn = cb.cnn
 AND wsd.corridor = cb.corridor
 AND wsd.limits = cb.limits
ORDER BY wsd.dist_deg;
$$;

GRANT EXECUTE ON FUNCTION public.schedules_near_closest_block(double precision, double precision) TO anon;
GRANT EXECUTE ON FUNCTION public.schedules_near_closest_block(double precision, double precision) TO authenticated;
GRANT EXECUTE ON FUNCTION public.schedules_near_closest_block(double precision, double precision) TO service_role;
