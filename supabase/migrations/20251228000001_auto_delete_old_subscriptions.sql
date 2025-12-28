-- Migration: Auto-delete subscriptions older than 90 days
-- Uses pg_cron to run daily cleanup

-- Create the cleanup function
CREATE OR REPLACE FUNCTION delete_old_subscriptions()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM public.subscriptions
    WHERE created_at < NOW() - INTERVAL '90 days';

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Schedule daily cleanup at 3am UTC
SELECT cron.schedule(
    'delete-old-subscriptions',
    '0 3 * * *',
    'SELECT delete_old_subscriptions()'
);
