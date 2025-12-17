# Cloudflare Workers Subscriptions Implementation Plan

This document describes the remaining work to fully implement the subscriptions API endpoints in the Cloudflare Workers backend. The original implementation existed in Python (commit `06514f2`) and needs to be ported to TypeScript.

## Current State

The subscription endpoints in `workers/src/routes/subscriptions.ts` are **stubs** that:
- Validate incoming requests via Zod schemas
- Return success responses (201, 200, 204)
- **Do NOT actually read/write to the database**

## Database Schema

The `subscriptions` table in Supabase has these columns (inferred from Python code):

| Column | Type | Notes |
|--------|------|-------|
| `device_token` | `text` | Primary key, unique constraint for upsert |
| `platform` | `text` | One of: `ios`, `android`, `web` |
| `schedule_block_sweep_id` | `integer` | FK to schedules table |
| `location` | `geography` | PostGIS point, stored as `SRID=4326;POINT(lon lat)` |
| `lead_minutes` | `integer` | How many minutes before sweep to notify (multiple of 15) |
| `last_notified_at` | `timestamp` | When user was last notified (nullable) |

---

## Tasks

### Task 1: Add Subscription Methods to SupabaseClient

**File:** `workers/src/supabase.ts`

Add these methods to the existing `SupabaseClient` class:

#### 1.1 `upsertSubscription()`

```typescript
async upsertSubscription(params: {
  deviceToken: string;
  platform: 'ios' | 'android' | 'web';
  scheduleBlockSweepId: number;
  latitude: number;
  longitude: number;
  leadMinutes: number;
}): Promise<SubscriptionRecord>
```

**Implementation details:**
- POST to `/rest/v1/subscriptions`
- Query param: `on_conflict=device_token`
- Header: `Prefer: resolution=merge-duplicates,return=representation`
- Body (array with single object):
  ```json
  [{
    "device_token": "...",
    "platform": "ios",
    "schedule_block_sweep_id": 12345,
    "location": "SRID=4326;POINT(-122.4194 37.7749)",
    "lead_minutes": 60
  }]
  ```
- Parse response and return the record

#### 1.2 `getSubscriptionByDeviceToken()`

```typescript
async getSubscriptionByDeviceToken(deviceToken: string): Promise<SubscriptionRecord | null>
```

**Implementation details:**
- GET `/rest/v1/subscriptions?device_token=eq.{deviceToken}&limit=1`
- Select: `device_token,platform,schedule_block_sweep_id,lead_minutes,last_notified_at`
- Return null if empty array, otherwise parse first record

#### 1.3 `deleteSubscription()`

```typescript
async deleteSubscription(deviceToken: string): Promise<boolean>
```

**Implementation details:**
- DELETE `/rest/v1/subscriptions?device_token=eq.{deviceToken}`
- Header: `Prefer: return=representation`
- Return true if deleted, false if not found

---

### Task 2: Add Zod Schema for SubscriptionRecord

**File:** `workers/src/models/index.ts`

```typescript
export const SubscriptionRecordSchema = z.object({
  device_token: z.string(),
  platform: z.enum(['ios', 'android', 'web']),
  schedule_block_sweep_id: z.number(),
  lead_minutes: z.number(),
  last_notified_at: z.string().nullable().optional(),
});

export type SubscriptionRecord = z.infer<typeof SubscriptionRecordSchema>;
```

---

### Task 3: Implement POST /subscriptions

**File:** `workers/src/routes/subscriptions.ts`

Replace the stub implementation:

```typescript
subscriptions.post(
  '/',
  zValidator('json', subscribeSchema),
  async (c) => {
    const data = c.req.valid('json');

    const supabase = new SupabaseClient({
      url: c.env.SUPABASE_URL,
      key: c.env.SUPABASE_KEY,
    });

    // 1. Upsert subscription to database
    const record = await supabase.upsertSubscription({
      deviceToken: data.device_token,
      platform: data.platform,
      scheduleBlockSweepId: data.schedule_block_sweep_id,
      latitude: data.latitude,
      longitude: data.longitude,
      leadMinutes: data.lead_minutes,
    });

    // 2. Fetch the schedule to compute next sweep window
    const schedule = await supabase.getScheduleByBlockSweepId(
      record.schedule_block_sweep_id
    );

    // 3. Compute next sweep window
    const rules = scheduleToRules(schedule);
    const { start, end } = nextSweepWindow(rules);

    // 4. Return response
    return c.json({
      device_token: record.device_token,
      platform: record.platform,
      schedule_block_sweep_id: record.schedule_block_sweep_id,
      lead_minutes: record.lead_minutes,
      next_sweep_start: start.toISOString(),
      next_sweep_end: end.toISOString(),
    }, 201);
  }
);
```

**Error handling:**
- 400: Invalid request body (Zod handles this)
- 404: Schedule not found for `schedule_block_sweep_id`
- 500: Database authentication error
- 502: Database connection error

---

### Task 4: Implement GET /subscriptions/:device_token

**File:** `workers/src/routes/subscriptions.ts`

```typescript
subscriptions.get('/:device_token', async (c) => {
  const deviceToken = c.req.param('device_token');

  const supabase = new SupabaseClient({
    url: c.env.SUPABASE_URL,
    key: c.env.SUPABASE_KEY,
  });

  // 1. Fetch subscription
  const record = await supabase.getSubscriptionByDeviceToken(deviceToken);
  if (!record) {
    return c.json({ error: 'Subscription not found' }, 404);
  }

  // 2. Fetch schedule and compute next sweep
  const schedule = await supabase.getScheduleByBlockSweepId(
    record.schedule_block_sweep_id
  );
  const rules = scheduleToRules(schedule);
  const { start, end } = nextSweepWindow(rules);

  // 3. Return response
  return c.json({
    device_token: record.device_token,
    platform: record.platform,
    schedule_block_sweep_id: record.schedule_block_sweep_id,
    lead_minutes: record.lead_minutes,
    next_sweep_start: start.toISOString(),
    next_sweep_end: end.toISOString(),
  });
});
```

---

### Task 5: Implement DELETE /subscriptions/:device_token

**File:** `workers/src/routes/subscriptions.ts`

```typescript
subscriptions.delete('/:device_token', async (c) => {
  const deviceToken = c.req.param('device_token');

  const supabase = new SupabaseClient({
    url: c.env.SUPABASE_URL,
    key: c.env.SUPABASE_KEY,
  });

  const deleted = await supabase.deleteSubscription(deviceToken);
  if (!deleted) {
    return c.json({ error: 'Subscription not found' }, 404);
  }

  return c.body(null, 204);
});
```

---

### Task 6: Add Tests

**File:** `workers/src/routes/subscriptions.test.ts` (new file)

Test cases to add:
1. POST creates new subscription and returns 201 with schedule info
2. POST updates existing subscription (upsert behavior)
3. POST returns 404 if schedule_block_sweep_id doesn't exist
4. POST returns 400 for invalid lead_minutes (not multiple of 15)
5. GET returns subscription with computed next sweep
6. GET returns 404 for unknown device token
7. DELETE removes subscription and returns 204
8. DELETE returns 404 for unknown device token

Use mocked Supabase responses (similar to existing test patterns).

---

### Task 7: CORS Production Configuration

**File:** `workers/src/index.ts`

Update the CORS configuration for production:

```typescript
app.use('/*', cors({
  origin: [
    'https://your-flutter-web-domain.com',
    'https://sweep-dreams.vercel.app',
    // Add your actual domains
  ],
  allowMethods: ['GET', 'POST', 'DELETE', 'HEAD', 'OPTIONS'],
  allowHeaders: ['Content-Type', 'Authorization'],
}));
```

Or use environment-based configuration:
```typescript
origin: c.env.CORS_ORIGINS?.split(',') || '*',
```

---

## Reference: Python Implementation

The original Python implementation can be found at commit `06514f2`:

| Python File | Purpose |
|------------|---------|
| `src/sweep_dreams/repositories/subscriptions.py` | Supabase CRUD for subscriptions |
| `src/sweep_dreams/services/subscriptions.py` | Business logic orchestration |
| `src/sweep_dreams/api/routes.py` | HTTP endpoint handlers |
| `src/sweep_dreams/api/models.py` | Request/response Pydantic models |

Key patterns from Python:
- Upsert uses `on_conflict=device_token` and `Prefer: resolution=merge-duplicates`
- Location stored as PostGIS geography: `SRID=4326;POINT(lon lat)` (note: longitude first!)
- Subscription response includes computed `next_sweep_start` and `next_sweep_end`
- `lead_minutes` must be a multiple of 15

---

## Testing Locally

```bash
cd workers
npm run dev

# Create subscription
curl -X POST http://localhost:8787/subscriptions \
  -H "Content-Type: application/json" \
  -d '{
    "device_token": "test-token-123",
    "platform": "ios",
    "schedule_block_sweep_id": 12345,
    "latitude": 37.7749,
    "longitude": -122.4194,
    "lead_minutes": 60
  }'

# Get subscription
curl http://localhost:8787/subscriptions/test-token-123

# Delete subscription
curl -X DELETE http://localhost:8787/subscriptions/test-token-123
```

---

## Deployment Checklist

- [ ] Implement Task 1-5 (core functionality)
- [ ] Add tests (Task 6)
- [ ] Configure CORS for production domains (Task 7)
- [ ] Verify `subscriptions` table exists in Supabase with correct schema
- [ ] Deploy with `npm run deploy`
- [ ] Test from Flutter app on real device
