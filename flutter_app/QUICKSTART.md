# Sweep Dreams Flutter App - Quick Start

## 🚀 Setup Instructions

The Flutter app is ready to use but needs platform-specific files generated first.

### Option 1: Automated Setup (Recommended)

Run the setup script:

```bash
cd flutter_app
./setup.sh
```

This will:
- Generate iOS, Android, web, and macOS platform folders
- Install all Flutter dependencies
- Configure iOS location permissions

### Option 2: Manual Setup

If you prefer to do it manually:

```bash
cd flutter_app

# Generate platform folders
flutter create --platforms=ios,android,web,macos .

# Install dependencies
flutter pub get
```

Then add iOS location permissions by editing `ios/Runner/Info.plist` and adding:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to find street sweeping schedules near you.</string>
```

## 📱 Running the App

### Choose Your Platform:

**Web (Easiest for testing):**
```bash
flutter run -d chrome
```

**macOS Desktop:**
```bash
flutter run -d macos
```

**iOS Simulator:**
```bash
# First, open iOS Simulator:
open -a Simulator

# Then run:
flutter run -d ios
```

**Android Emulator:**
```bash
# Start an Android emulator first, then:
flutter run -d android
```

## ⚙️ Configuration

### API Endpoint

By default, the app connects to `http://localhost:8000`. 

To change this, edit `lib/services/api_service.dart`:

```dart
ApiService({this.baseUrl = 'http://YOUR_API_URL'});
```

For testing on physical devices, you'll need to use your computer's IP address:
- Find your IP: `ifconfig | grep "inet " | grep -v 127.0.0.1`
- Update the baseUrl: `http://YOUR_IP:8000`

### Running Backend

Make sure your Sweep Dreams API is running:

```bash
cd ..  # Back to project root
uv run uvicorn sweep_dreams.api:app --reload
```

## 🎨 Features

- ✅ GPS location-based lookup
- ✅ Beautiful Material Design 3 UI
- ✅ Smooth animations and transitions
- ✅ Multiple schedule support with tabs
- ✅ Real-time date/time formatting
- ✅ Status indicators (info/success/error)

## 🔍 Troubleshooting

### "No devices found"

This means you need to either:
1. Run the setup script to generate platform folders
2. Open an iOS Simulator or Android Emulator
3. Use `-d chrome` or `-d macos` to run on available platforms

### Location permissions not working

Make sure the Info.plist permissions are added (see Manual Setup above).

### API connection fails

1. Check that your backend is running
2. Verify the baseUrl in `lib/services/api_service.dart`
3. For physical devices, use your computer's IP instead of localhost
4. Check CORS settings on your backend if running on web

## 📖 Project Structure

```
flutter_app/
├── lib/
│   ├── main.dart                   # App entry point
│   ├── theme/app_theme.dart        # Colors & styling
│   ├── models/schedule_response.dart
│   ├── services/
│   │   ├── api_service.dart        # API client
│   │   └── location_service.dart   # GPS
│   ├── screens/home_screen.dart    # Main UI
│   └── widgets/
│       ├── schedule_card.dart
│       └── status_banner.dart
└── pubspec.yaml                    # Dependencies
```

## 🎯 Next Steps

1. Run `./setup.sh` to generate platform files
2. Start your backend API
3. Run `flutter run -d chrome` to test in browser
4. Open iOS Simulator and run `flutter run` for mobile testing

