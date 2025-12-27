-- Change schedules_near distance from ~5m to ~10m
CREATE OR REPLACE FUNCTION "public"."schedules_near"("lon" double precision, "lat" double precision) RETURNS SETOF "public"."schedules"
    LANGUAGE "sql" STABLE
    AS $$
  with params as (
    select
      extensions.st_setsrid(
        extensions.st_point(lon, lat), 4326
      ) as p,
      0.0001::double precision as max_deg_dist   -- ~10m
  )
  select s.*
  from public.schedules s, params
  where extensions.st_distance(s.line, p) <= max_deg_dist
  order by extensions.st_distance(s.line, p);
$$;
