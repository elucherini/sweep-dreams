-- Add subscription_type column to distinguish sweeping vs parking regulation subscriptions
-- Default to 'sweeping' for all existing records

-- Add the column with a default value
ALTER TABLE public.subscriptions
ADD COLUMN subscription_type text NOT NULL DEFAULT 'sweeping';

-- Add check constraint to ensure valid values
ALTER TABLE public.subscriptions
ADD CONSTRAINT subscriptions_type_check
CHECK (subscription_type IN ('sweeping', 'parking'));

-- Update all existing records to 'sweeping' (redundant due to DEFAULT, but explicit)
UPDATE public.subscriptions
SET subscription_type = 'sweeping'
WHERE subscription_type IS NULL OR subscription_type = '';

-- Add index for filtering by subscription type
CREATE INDEX subscriptions_type_idx ON public.subscriptions (subscription_type);
