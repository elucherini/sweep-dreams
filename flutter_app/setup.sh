#!/bin/bash

# Setup script for Sweep Dreams Flutter app
echo "🚀 Setting up Flutter platform support..."

cd "$(dirname "$0")"

# Create platform folders for iOS, Android, Web, and macOS
echo "📱 Generating platform-specific code..."
flutter create --platforms=ios,android,web,macos .

# Get dependencies
echo "📦 Installing Flutter dependencies..."
flutter pub get

# Configure iOS location permissions
echo "🔐 Configuring iOS location permissions..."
if [ -f "ios/Runner/Info.plist" ]; then
    # The Info.plist will be created by flutter create
    # We need to add location permissions
    /usr/libexec/PlistBuddy -c "Add :NSLocationWhenInUseUsageDescription string 'We need your location to find street sweeping schedules near you.'" ios/Runner/Info.plist 2>/dev/null || echo "Location permission already added or plist not found"
fi

echo "✅ Setup complete!"
echo ""
echo "To run the app:"
echo "  • iOS Simulator:     flutter run -d ios"
echo "  • Android Emulator:  flutter run -d android"
echo "  • Web Browser:       flutter run -d chrome"
echo "  • macOS Desktop:     flutter run -d macos"
echo ""
echo "Make sure to update the API endpoint in lib/services/api_service.dart"
echo "if your backend is not running on localhost:8000"

