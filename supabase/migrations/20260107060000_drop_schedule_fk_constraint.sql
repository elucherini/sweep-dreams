-- Drop the foreign key constraint on subscriptions.schedule_block_sweep_id
-- This allows timing subscriptions to reference parking_regulations.id
-- instead of only schedules.block_sweep_id
ALTER TABLE subscriptions
DROP CONSTRAINT IF EXISTS subscriptions_schedule_block_sweep_id_fkey;
