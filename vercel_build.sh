#!/usr/bin/env bash
set -e

# Download Flutter SDK
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$PWD/flutter/bin:$PATH"

cd flutter_app

flutter config --enable-web
flutter precache --web

flutter pub get
flutter build web --release


