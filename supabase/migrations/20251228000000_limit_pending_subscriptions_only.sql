-- Migration: Only count pending (not yet notified) subscriptions toward the limit
-- This allows users to keep getting new alerts after old ones have been sent

CREATE OR REPLACE FUNCTION check_subscription_limit()
RETURNS TRIGGER AS $$
DECLARE
    subscription_count INTEGER;
    max_subscriptions CONSTANT INTEGER := 5;
BEGIN
    SELECT COUNT(*) INTO subscription_count
    FROM public.subscriptions
    WHERE device_token = NEW.device_token
      AND last_notified_at IS NULL;

    IF subscription_count >= max_subscriptions THEN
        RAISE EXCEPTION 'Maximum subscriptions (%) per device exceeded', max_subscriptions;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
