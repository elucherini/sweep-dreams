-- Remove LIMIT 10 from parking_regulations_near function
-- Allow all matching regulations to be returned

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
        SELECT extensions.ST_SetSRID(extensions.ST_MakePoint(lon, lat), 4326) AS geom
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
    WHERE extensions.ST_DWithin(
        r.line::extensions.geography,
        p.geom::extensions.geography,
        radius_meters
    )
    ORDER BY distance_meters ASC;
$$;
