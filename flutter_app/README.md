# Sweep Dreams Flutter App

A beautiful, contemporary Flutter mobile app for checking street sweeping schedules in San Francisco.

## Features

- 🎨 Modern Material Design 3 UI with smooth animations
- 📍 Location-based schedule lookup using device GPS
- 📅 Real-time street sweeping window calculations
- 🔄 Multiple schedule support with swipeable tabs
- ⚡ Fast and responsive with beautiful transitions
- 🎯 Clean architecture with proper state management

## Prerequisites

- Flutter SDK (>=3.2.0)
- Dart SDK
- iOS Simulator / Android Emulator or physical device
- Running Sweep Dreams API backend

## Getting Started

### 1. Install Dependencies

```bash
cd flutter_app
flutter pub get
```

### 2. Configure API Endpoint

By default, the app connects to `http://localhost:8787`. To change this:

Edit `lib/services/api_service.dart` and update the `baseUrl`:

```dart
ApiService({this.baseUrl = 'http://your-api-url.com'});
```

Or pass it when creating the ApiService in `main.dart`.

### 3. iOS Setup (Location Permissions)

Add the following to `ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to find street sweeping schedules near you.</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>We need your location to find street sweeping schedules near you.</string>
```

### 4. Android Setup (Location Permissions)

The required permissions are already configured in the geolocator package, but ensure your `android/app/src/main/AndroidManifest.xml` includes:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

### 5. Run the App

```bash
flutter run
```

For specific platforms:

```bash
# iOS
flutter run -d ios

# Android
flutter run -d android

# Web (requires additional configuration for geolocation)
flutter run -d chrome
```

## Project Structure

```
flutter_app/
├── lib/
│   ├── main.dart                 # App entry point
│   ├── theme/
│   │   └── app_theme.dart        # Color scheme and theme definitions
│   ├── models/
│   │   └── schedule_response.dart # Data models
│   ├── services/
│   │   ├── api_service.dart      # API client
│   │   └── location_service.dart # GPS location handling
│   ├── screens/
│   │   └── home_screen.dart      # Main screen
│   └── widgets/
│       ├── schedule_card.dart    # Schedule detail card
│       └── status_banner.dart    # Status message banner
├── pubspec.yaml                  # Dependencies
└── README.md
```

## Key Technologies

- **Flutter**: Cross-platform UI framework
- **Provider**: State management
- **Geolocator**: GPS location services
- **HTTP**: REST API communication
- **Intl**: Date/time formatting

## Design Highlights

- **Gradient Background**: Radial gradient with soft blue tones
- **Smooth Animations**: Fade and slide transitions for result cards
- **Material Design 3**: Modern card designs with proper elevation
- **Responsive Layout**: Works on all screen sizes
- **Accessible**: Proper color contrast and semantic structure

## API Integration

The app expects the backend to return data in the following format:

```json
{
  "request_point": {
    "latitude": 37.7749,
    "longitude": -122.4194
  },
  "schedules": [
    {
      "schedule": {
        "full_name": "Schedule Name",
        "block_side": "Left",
        "limits": "Street limits",
        "from_hour": 8,
        "to_hour": 10,
        "week_day": "Monday"
      },
      "next_sweep_start": "2024-01-15T08:00:00-08:00",
      "next_sweep_end": "2024-01-15T10:00:00-08:00"
    }
  ],
  "timezone": "America/Los_Angeles"
}
```

## Development

### Hot Reload

Flutter supports hot reload for rapid development:

- Press `r` in the terminal to hot reload
- Press `R` to hot restart
- Press `q` to quit

### Building for Production

```bash
# iOS
flutter build ios

# Android
flutter build apk --release
flutter build appbundle --release
```

## Troubleshooting

### Location Not Working

1. Ensure location services are enabled on the device
2. Grant location permissions when prompted
3. For iOS simulator, use Feature > Location > Custom Location
4. For Android emulator, set location via Extended Controls

### API Connection Issues

1. If running on physical device, ensure backend is accessible
2. Update baseUrl in `api_service.dart` to use your computer's IP address
3. For Android, use `http://10.0.2.2:8787` to access localhost
4. Ensure no CORS issues on the backend

## License

See the main project LICENSE file.

