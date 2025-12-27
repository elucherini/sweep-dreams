-- Change schedules_near radius back to 100m
CREATE OR REPLACE FUNCTION "public"."schedules_near"("lon" double precision, "lat" double precision)
RETURNS TABLE (
    "cnn" bigint,
    "corridor" text,
    "limits" text,
    "cnn_right_left" text,
    "block_side" text,
    "full_name" text,
    "week_day" text,
    "from_hour" smallint,
    "to_hour" smallint,
    "week1" boolean,
    "week2" boolean,
    "week3" boolean,
    "week4" boolean,
    "week5" boolean,
    "holidays" boolean,
    "block_sweep_id" bigint,
    "line" extensions.geometry(LineString,4326),
    "created_at" timestamp without time zone,
    "distance_meters" double precision
)
LANGUAGE "sql" STABLE
AS $$
  with params as (
    select
      extensions.st_setsrid(
        extensions.st_point(lon, lat), 4326
      ) as p,
      0.001::double precision as max_deg_dist   -- ~100m
  )
  select
    s.cnn,
    s.corridor,
    s.limits,
    s.cnn_right_left,
    s.block_side,
    s.full_name,
    s.week_day,
    s.from_hour,
    s.to_hour,
    s.week1,
    s.week2,
    s.week3,
    s.week4,
    s.week5,
    s.holidays,
    s.block_sweep_id,
    s.line,
    s.created_at,
    extensions.st_distance(s.line::extensions.geography, p::extensions.geography) as distance_meters
  from public.schedules s, params
  where extensions.st_distance(s.line, p) <= max_deg_dist
  order by extensions.st_distance(s.line, p);
$$;
