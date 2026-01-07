-- Rename subscription_type value from 'parking' to 'timing'

-- First drop the old constraint
ALTER TABLE public.subscriptions
DROP CONSTRAINT subscriptions_type_check;

-- Update any existing 'parking' values to 'timing'
UPDATE public.subscriptions
SET subscription_type = 'timing'
WHERE subscription_type = 'parking';

-- Add the new constraint with 'timing' instead of 'parking'
ALTER TABLE public.subscriptions
ADD CONSTRAINT subscriptions_type_check
CHECK (subscription_type IN ('sweeping', 'timing'));
