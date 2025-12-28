-- Migration: Allow multiple subscriptions per device
-- This changes the unique constraint from device_token alone
-- to the combination of (device_token, schedule_block_sweep_id)

-- Step 1: Drop the existing unique constraint on device_token
ALTER TABLE "public"."subscriptions"
DROP CONSTRAINT "subscriptions_device_token_key";

-- Step 2: Add new composite unique constraint
-- A device can subscribe to multiple schedules, but only once per schedule
ALTER TABLE "public"."subscriptions"
ADD CONSTRAINT "subscriptions_device_schedule_unique"
UNIQUE ("device_token", "schedule_block_sweep_id");

-- Step 3: Add an index for efficient lookups by device_token
-- (The old unique constraint provided this implicitly)
CREATE INDEX IF NOT EXISTS "subscriptions_device_token_idx"
ON "public"."subscriptions" ("device_token");

-- Step 4: Add a limit on subscriptions per device via trigger
-- This prevents abuse - e.g., max 10 subscriptions per device
CREATE OR REPLACE FUNCTION check_subscription_limit()
RETURNS TRIGGER AS $$
DECLARE
    subscription_count INTEGER;
    max_subscriptions CONSTANT INTEGER := 10;
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

CREATE TRIGGER enforce_subscription_limit
BEFORE INSERT ON public.subscriptions
FOR EACH ROW
EXECUTE FUNCTION check_subscription_limit();
