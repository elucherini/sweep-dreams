# Sweep Dreams Workers API

Cloudflare Workers-based REST API for street sweeping schedule lookups.

## Why Cloudflare Workers?

- **0ms cold starts** (vs 30-60s on Render free tier)
- **Global edge deployment** with automatic CDN caching
- **100k requests/day free tier** (vs 750 hours/month on Render)
- **Sub-50ms response times** worldwide

## Architecture

This Workers API replaces the Python FastAPI application. Python remains for:
- ETL pipeline (GitHub Actions)
- Notification scripts (GitHub Actions)
- Shared domain logic (calendar computations, models)

## Project Structure

```
workers/
├── src/
│   ├── index.ts           # Main app entry point
│   ├── models/            # Zod schemas (port of Pydantic models)
│   ├── lib/
│   │   ├── calendar.ts    # Sweep window computation logic
│   │   └── formatting.ts  # Human-readable rule formatting
│   ├── routes/
│   │   ├── schedules.ts   # /check-location endpoint
│   │   └── subscriptions.ts # Subscription management
│   └── supabase.ts        # Lightweight Supabase HTTP client
├── package.json
├── tsconfig.json
├── wrangler.toml          # Cloudflare Workers config
└── vitest.config.ts       # Test configuration
```

## Development

### Prerequisites

- Node.js 18+ (Workers uses V8)
- npm or yarn
- Wrangler CLI (installed via npm)

### Setup

```bash
cd workers
npm install
```

### Local Development

```bash
# Create .dev.vars file with environment variables
echo "SUPABASE_URL=https://your-project.supabase.co" > .dev.vars
echo "SUPABASE_KEY=your-anon-key" >> .dev.vars

# Start dev server (hot reload enabled)
npm run dev

# Visit http://localhost:8787/health
```

### Testing

```bash
# Run unit tests
npm test

# Run tests in watch mode
npm test -- --watch

# Type check
npm run type-check
```

## Deployment

### Prerequisites

1. Cloudflare account
2. Wrangler CLI authenticated: `npx wrangler login`
3. Secrets configured (see below)

### Set Production Secrets

```bash
npx wrangler secret put SUPABASE_URL
# Enter: https://your-project.supabase.co

npx wrangler secret put SUPABASE_KEY
# Enter: your-supabase-anon-key
```

### Deploy

```bash
npm run deploy
```

This deploys to `https://sweep-dreams-api.<your-subdomain>.workers.dev`

### Automatic Deployment

GitHub Actions automatically deploys on push to `main` when `workers/**` files change.

Required GitHub secret:
- `CLOUDFLARE_API_TOKEN` - Get from Cloudflare dashboard → API Tokens

## API Endpoints

### GET /health

Health check endpoint.

**Response:**
```json
{
  "status": "ok"
}
```

### GET /check-location

Find street sweeping schedules near a coordinate.

**Query Parameters:**
- `latitude` (float, -90 to 90)
- `longitude` (float, -180 to 180)

**Example:**
```bash
curl "https://your-workers-url.workers.dev/check-location?latitude=37.7749&longitude=-122.4194"
```

**Response:**
```json
{
  "request_point": {
    "latitude": 37.7749,
    "longitude": -122.4194
  },
  "schedules": [
    {
      "block_sweep_id": 12345,
      "corridor": "Main St",
      "limits": "100-200",
      "human_rules": ["Every 1st, 3rd Monday at 8am-10am"],
      "next_sweep_start": "2025-01-06T08:00:00-08:00",
      "next_sweep_end": "2025-01-06T10:00:00-08:00"
    }
  ],
  "timezone": "America/Los_Angeles"
}
```

### Subscription Endpoints

- `POST /subscriptions` - Create notification subscription
- `GET /subscriptions/:device_token` - Get subscription
- `DELETE /subscriptions/:device_token` - Delete subscription

*(Implementation in progress)*

## Key Implementation Details

### Calendar Logic

The most critical part of the migration is the calendar computation logic in [src/lib/calendar.ts](src/lib/calendar.ts):

- `nextSweepWindow()` - Computes next sweep window for a raw schedule
- `nextSweepWindowFromRule()` - Computes from a recurring rule
- Handles midnight-crossing windows (e.g., 10pm-2am)
- Searches up to 13 months ahead for next occurrence

### Weekday Enum Mapping

JavaScript `Date.getDay()` uses Sunday=0, but our domain model uses Monday=0:

```typescript
// Convert JavaScript weekday to our enum
const ourWeekday = (jsWeekday + 6) % 7;
```

### Supabase RPC Calls

No Supabase SDK - just raw `fetch()` calls to REST API:

```typescript
const response = await fetch(`${url}/rest/v1/rpc/schedules_near`, {
  method: 'POST',
  headers: {
    'apikey': key,
    'Authorization': `Bearer ${key}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({ lon, lat }),
});
```

## Performance

### Expected Metrics

| Metric | Target |
|--------|--------|
| Cold start | <100ms |
| Hot response | <50ms |
| P99 latency | <200ms |

### Monitoring

View metrics in Cloudflare dashboard:
- Request volume
- Error rate
- Response times (P50, P95, P99)
- Edge location breakdown

## Troubleshooting

### Check logs

```bash
npx wrangler tail --format=pretty
```

### Common issues

**Error: "Missing binding SUPABASE_URL"**
- Run `npx wrangler secret put SUPABASE_URL`

**CORS errors from Flutter app**
- Update `origin` in [src/index.ts](src/index.ts) CORS middleware

**Calendar computation errors**
- Check test suite: `npm test`
- Verify weekday enum mapping matches Python domain model

## Migration Checklist

- [x] Port TypeScript models and Zod schemas
- [x] Port calendar logic
- [x] Port formatting utilities
- [x] Create Supabase client
- [x] Implement /check-location route
- [x] Add unit tests for calendar logic
- [x] Create GitHub Actions deployment workflow
- [ ] Configure Cloudflare secrets
- [ ] Update Flutter app API URL
- [ ] Deploy to production
- [ ] Update documentation
- [ ] Remove Render deployment

## Resources

- [Cloudflare Workers Docs](https://developers.cloudflare.com/workers/)
- [Hono Framework](https://hono.dev/)
- [Wrangler CLI](https://developers.cloudflare.com/workers/wrangler/)
- [Vitest](https://vitest.dev/)
