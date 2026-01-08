-- Use index-friendly spatial predicates for proximity filters.
--
-- Motivation:
-- - `ST_Distance(...) <= radius` can defeat GiST index usage.
-- - Prefer `ST_DWithin(...)` (plus optional bbox prefilter) to keep lookups fast,
--   especially when the map UI generates many requests.

-- 1) schedules_near: switch candidates filter to ST_DWithin
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
    extensions.ST_Distance(s.line::extensions.geography, params.p::extensions.geography) AS distance_meters
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
  wsd.distance_meters,
  (CASE WHEN wsd.dist_to_left_m <= wsd.dist_to_right_m THEN 'L' ELSE 'R' END = wsd.cnn_right_left) AS is_user_side,
  extensions.ST_AsGeoJSON(wsd.line)::jsonb AS line_geojson
FROM with_side_distances wsd
ORDER BY wsd.dist_deg;
$$;

GRANT EXECUTE ON FUNCTION public.schedules_near(double precision, double precision) TO anon;
GRANT EXECUTE ON FUNCTION public.schedules_near(double precision, double precision) TO authenticated;
GRANT EXECUTE ON FUNCTION public.schedules_near(double precision, double precision) TO service_role;

-- 2) schedules_near_closest_block: switch candidates filter to ST_DWithin
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
    extensions.ST_Distance(s.line::extensions.geography, params.p::extensions.geography) AS distance_meters
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
  wsd.distance_meters,
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

-- 3) parking_regulations_near: add geometry prefilter to use GiST(line) index
CREATE OR REPLACE FUNCTION public.parking_regulations_near(
    lon double precision,
    lat double precision,
    radius_meters double precision DEFAULT 25.0
)
RETURNS TABLE (
    id bigint,
    regulation text,
    days text,
    hrs_begin smallint,
    hrs_end smallint,
    hour_limit smallint,
    rpp_area1 text,
    rpp_area2 text,
    exceptions text,
    from_time text,
    to_time text,
    neighborhood text,
    line extensions.geometry,
    distance_meters double precision
)
LANGUAGE sql
STABLE
AS $$
    WITH user_point AS (
        SELECT
          extensions.ST_SetSRID(extensions.ST_MakePoint(lon, lat), 4326) AS geom,
          (radius_meters / 85000.0) AS radius_deg
    )
    SELECT
        r.id,
        r.regulation,
        r.days,
        r.hrs_begin,
        r.hrs_end,
        r.hour_limit,
        r.rpp_area1,
        r.rpp_area2,
        r.exceptions,
        r.from_time,
        r.to_time,
        r.neighborhood,
        r.line,
        extensions.ST_Distance(r.line::extensions.geography, p.geom::extensions.geography) AS distance_meters
    FROM public.parking_regulations r, user_point p
    WHERE extensions.ST_DWithin(r.line, p.geom, p.radius_deg)
      AND extensions.ST_DWithin(
        r.line::extensions.geography,
        p.geom::extensions.geography,
        radius_meters
      )
    ORDER BY distance_meters ASC;
$$;

GRANT EXECUTE ON FUNCTION public.parking_regulations_near(double precision, double precision, double precision) TO anon;
GRANT EXECUTE ON FUNCTION public.parking_regulations_near(double precision, double precision, double precision) TO service_role;

-- 4) parking_regulation_nearest: add geometry prefilter to use GiST(line) index
CREATE OR REPLACE FUNCTION public.parking_regulation_nearest(
  lon double precision,
  lat double precision,
  radius_meters double precision DEFAULT 150.0
)
RETURNS TABLE (
  id bigint,
  regulation text,
  days text,
  hrs_begin smallint,
  hrs_end smallint,
  hour_limit smallint,
  rpp_area1 text,
  rpp_area2 text,
  exceptions text,
  from_time text,
  to_time text,
  neighborhood text,
  line extensions.geometry,
  distance_meters double precision
)
LANGUAGE sql
STABLE
AS $$
WITH user_point AS (
  SELECT
    extensions.ST_SetSRID(extensions.ST_MakePoint(lon, lat), 4326) AS geom,
    (radius_meters / 85000.0) AS radius_deg
)
SELECT
  r.id,
  r.regulation,
  r.days,
  r.hrs_begin,
  r.hrs_end,
  r.hour_limit,
  r.rpp_area1,
  r.rpp_area2,
  r.exceptions,
  r.from_time,
  r.to_time,
  r.neighborhood,
  r.line,
  extensions.ST_Distance(r.line::extensions.geography, p.geom::extensions.geography) AS distance_meters
FROM public.parking_regulations r, user_point p
WHERE extensions.ST_DWithin(r.line, p.geom, p.radius_deg)
  AND extensions.ST_DWithin(
    r.line::extensions.geography,
    p.geom::extensions.geography,
    radius_meters
  )
ORDER BY distance_meters ASC
LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.parking_regulation_nearest(double precision, double precision, double precision) TO anon;
GRANT EXECUTE ON FUNCTION public.parking_regulation_nearest(double precision, double precision, double precision) TO service_role;
