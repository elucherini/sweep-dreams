-- Migration: Reduce max subscriptions per device from 10 to 5

CREATE OR REPLACE FUNCTION check_subscription_limit()
RETURNS TRIGGER AS $$
DECLARE
    subscription_count INTEGER;
    max_subscriptions CONSTANT INTEGER := 5;
BEGIN
    SELECT COUNT(*) INTO subscription_count
    FROM public.subscriptions
    WHERE device_token = NEW.device_token;

    IF subscription_count >= max_subscriptions THEN
        RAISE EXCEPTION 'Maximum subscriptions (%) per device exceeded', max_subscriptions;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
