# Sweep Dreams 🧹

Sweep Dreams tells you when your block is getting cleaned in San Francisco. Let the app find your location and see when you need to move your car.

For San Francisco car owners who've had one too many $105 tickets.

## What it does

- **Location lookup**: Use your current location to find the next street sweeping window
- **Mobile-friendly**: Native iOS app, plus a web version. Android coming soon!
- **Notifications**: Sends reminders before street sweeping

## Stack

### Backend
- **Python 3.13** with FastAPI
- **Supabase** (PostgreSQL + PostGIS) for storage and geospatial queries
- **uv** for dependency management

### Mobile/Web
- **Flutter** (Dart) for cross-platform apps
- Firebase Cloud Messaging for push notifications

## API

The backend exposes a simple endpoint:

```
GET /check-location?latitude=37.7749&longitude=-122.4194
```

Returns the nearest street segment and its next sweeping window in Pacific time.

## Local Development

```bash
# Backend
uv sync
uv run uvicorn sweep_dreams.api:app --reload

# Flutter app
cd flutter_app
flutter run
```

## Environment Variables

```
SUPABASE_URL=your-project-url
SUPABASE_KEY=your-anon-key
```

