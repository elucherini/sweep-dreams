-- Allow lead_minutes = 0 for timing subscriptions (e.g., "notify when restriction starts")
ALTER TABLE subscriptions DROP CONSTRAINT subscriptions_lead_minutes_check;
ALTER TABLE subscriptions ADD CONSTRAINT subscriptions_lead_minutes_check CHECK (lead_minutes >= 0);
