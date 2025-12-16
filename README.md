# Sweep Dreams 🧹

Sweep Dreams tells you when your block is getting cleaned in San Francisco. Let the app find your location and see when you need to move your car.

For San Francisco car owners who've had one too many $105 tickets.

## What it does

- **Location lookup**: Use your current location to find the next street sweeping window
- **Mobile-friendly**: Native iOS app, plus a web version. Android coming soon!
- **Notifications**: Sends reminders before street sweeping

## Stack

### API (Cloudflare Workers)
- **TypeScript** with Hono framework
- **Cloudflare Workers** - 0ms cold starts, global edge deployment
- **Supabase** (PostgreSQL + PostGIS) for storage and geospatial queries
- See [workers/README.md](workers/README.md) for details

### Data Pipeline (Python)
- **Python 3.13** for ETL and notifications
- **uv** for dependency management
- Runs daily in GitHub Actions
- Shared domain logic (calendar computations, models)

### Mobile/Web
- **Flutter** (Dart) for cross-platform apps
- Firebase Cloud Messaging for push notifications

## API

The API is deployed on Cloudflare Workers:

```
GET /check-location?latitude=37.7749&longitude=-122.4194
```

Returns the nearest street segment and its next sweeping window in Pacific time.

## Local Development

```bash
# API (Cloudflare Workers)
cd workers
npm install
npm run dev
# Visit http://localhost:8787/health

# Flutter app
cd flutter_app
flutter run

# Python ETL/scripts
uv sync
uv run python src/sweep_dreams/etl/schedules_etl.py
```

## Environment Variables

### Workers (create `workers/.dev.vars`)
```
SUPABASE_URL=your-project-url
SUPABASE_KEY=your-anon-key
```

### Python (create `.env`)
```
SUPABASE_URL=your-project-url
SUPABASE_KEY=your-service-role-key
SUPABASE_TABLE=schedules
```

