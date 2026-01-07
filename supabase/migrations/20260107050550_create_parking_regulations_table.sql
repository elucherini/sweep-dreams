-- Create parking_regulations table for SF parking regulations data
-- Source: SF Open Data - Parking regulations (except non-metered color curb)

CREATE TABLE public.parking_regulations (
    id bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,

    -- Core regulation info
    regulation text NOT NULL,           -- 'Time limited', 'No parking any time', etc.
    days text,                          -- 'M-F', 'M-Su', 'M-Sa'
    hrs_begin smallint,                 -- 900 = 9:00 AM (military-style)
    hrs_end smallint,                   -- 1800 = 6:00 PM
    hour_limit smallint,                -- 2, 3, 4 hour limit (from HRLIMIT column)

    -- RPP (Residential Permit Parking) areas
    rpp_area1 text,                     -- Primary RPP area: 'N', 'L', 'K', etc.
    rpp_area2 text,                     -- Secondary RPP area (some blocks have 2)
    rpp_area3 text,                     -- Tertiary (rare)

    -- Human-readable info
    reg_details text,                   -- Additional details/exceptions
    exceptions text,                    -- 'Yes. RPP holders are exempt...'
    from_time text,                     -- '9am' (human-readable)
    to_time text,                       -- '6pm' (human-readable)

    -- Location metadata
    neighborhood text,                  -- 'Inner Richmond', 'Marina', etc.
    supervisor_district text,           -- '1', '2', etc.
    length_ft real,                     -- Segment length in feet

    -- Geometry (line segments representing curb/street edge)
    line extensions.geometry(MultiLineString, 4326) NOT NULL,

    -- Audit fields
    source_objectid bigint,             -- Original objectid from SF data
    enacted date,                       -- When regulation was enacted
    data_as_of timestamptz,
    created_at timestamptz DEFAULT now()
);

-- Spatial index for fast proximity queries
CREATE INDEX parking_regulations_line_gix
    ON public.parking_regulations USING gist (line);

-- Index for filtering by regulation type
CREATE INDEX parking_regulations_regulation_idx
    ON public.parking_regulations (regulation);

-- Index for RPP area lookups
CREATE INDEX parking_regulations_rpp_idx
    ON public.parking_regulations (rpp_area1);

-- Index for source_objectid (for upsert operations during ETL)
CREATE UNIQUE INDEX parking_regulations_source_objectid_idx
    ON public.parking_regulations (source_objectid);

-- Enable RLS but allow anonymous read access (similar to schedules table)
ALTER TABLE public.parking_regulations ENABLE ROW LEVEL SECURITY;

-- Policy for anonymous read access
CREATE POLICY "Allow anonymous read access"
    ON public.parking_regulations
    FOR SELECT
    TO anon
    USING (true);

-- Policy for service role full access
CREATE POLICY "Allow service role full access"
    ON public.parking_regulations
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Grant necessary permissions
GRANT SELECT ON public.parking_regulations TO anon;
GRANT ALL ON public.parking_regulations TO service_role;
