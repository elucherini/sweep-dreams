#!/usr/bin/env bash
set -e

echo "=== Starting Flutter build ==="
echo "Current directory: $(pwd)"
echo "Contents: $(ls -la)"

# Download Flutter SDK (shallow clone for speed)
git clone https://github.com/flutter/flutter.git -b stable --depth 1
export PATH="$PWD/flutter/bin:$PATH"

# Verify Flutter installation
flutter --version

# Navigate to flutter_app directory
cd flutter_app
echo "=== Changed to flutter_app ==="
echo "Current directory: $(pwd)"
echo "Contents: $(ls -la)"
echo "Checking for lib/main.dart: $(ls -la lib/main.dart)"

# Configure Flutter for web
flutter config --enable-web
flutter precache --web

# Get dependencies and build
flutter pub get

# Build with environment variable for API URL
echo "Building with API_URL: $API_URL"
flutter build web --release --dart-define=API_URL="$API_URL"

echo "=== Build complete ==="
echo "Build output location: $(pwd)/build/web"


