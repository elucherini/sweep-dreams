# Sweep Dreams

Street sweeping schedule lookup for San Francisco. Find your location and see when you need to move your car.

For SF car owners who've had one too many $105 tickets.

## Features

- **Location-based lookup**: Find the next street sweeping window for your block
- **Parking regulations**: See time-limited parking rules nearby
- **Push notifications**: Get reminders before sweeping starts
- **Cross-platform**: iOS, Android, and web

## Stack

| Component | Tech |
|-----------|------|
| API | Cloudflare Workers, TypeScript, Hono |
| Database | Supabase (PostgreSQL + PostGIS) |
| Mobile/Web | Flutter, Firebase Cloud Messaging |
| ETL | Python 3.13, uv, GitHub Actions |

## API

```
GET /api/check-location?latitude=37.7749&longitude=-122.4194&radius=100
```

Returns nearest sweeping schedule and parking regulations in Pacific time.

## Local Development

```bash
# API
cd workers && npm install && npm run dev

# Flutter app
cd flutter_app && flutter run

# Python ETL
uv sync && uv run python src/sweep_dreams/etl/schedules_etl.py
```

## Environment Variables

### Workers (`workers/.dev.vars`)
```
SUPABASE_URL=your-project-url
SUPABASE_KEY=your-anon-key
```

### Python (`.env`)
```
SUPABASE_URL=your-project-url
SUPABASE_KEY=your-service-role-key
SUPABASE_TABLE=schedules
```
