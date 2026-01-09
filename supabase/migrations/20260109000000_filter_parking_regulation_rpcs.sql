-- Filter parking regulation RPCs to timing-limited only.
--
-- The UI/notifications only support time-limited (aka "timing limited") parking rules,
-- and hour_limit must be positive for deadlines/labels to make sense.

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
      AND r.hour_limit IS NOT NULL
      AND r.hour_limit > 0
      AND lower(trim(r.regulation)) IN ('time limited', 'timing limited')
    ORDER BY distance_meters ASC;
$$;

GRANT EXECUTE ON FUNCTION public.parking_regulations_near(double precision, double precision, double precision) TO anon;
GRANT EXECUTE ON FUNCTION public.parking_regulations_near(double precision, double precision, double precision) TO service_role;

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
  AND r.hour_limit IS NOT NULL
  AND r.hour_limit > 0
  AND lower(trim(r.regulation)) IN ('time limited', 'timing limited')
ORDER BY distance_meters ASC
LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.parking_regulation_nearest(double precision, double precision, double precision) TO anon;
GRANT EXECUTE ON FUNCTION public.parking_regulation_nearest(double precision, double precision, double precision) TO service_role;

