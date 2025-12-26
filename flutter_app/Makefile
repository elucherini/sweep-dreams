.PHONY: web web-release ios-sign ios ipa appbundle run run-ios build-and-run build-and-run-ios build-and-run-android debug debug-ios-device ios-device android-device clean lint test format

# Load local config (API URLs, device name, etc.)
-include .env.mk

# ============================================================================
# Build Targets
# ============================================================================

web:
	flutter build web

web-release:
	flutter build web --release

ios-sign:
	flutter build ios

ios:
	flutter build ios --no-codesign

ipa:
	flutter build ipa --release --dart-define=API_URL=$(API_URL_PROD)

appbundle:
	flutter build appbundle --release --dart-define=API_URL=$(API_URL_PROD)

# ============================================================================
# Run Targets
# ============================================================================

run:
	flutter run -d chrome --web-port=8090

run-ios:
	flutter run -d iPhone

build-and-run: web
	$(MAKE) run

build-and-run-ios: ios
	$(MAKE) run-ios

build-and-run-android:
	flutter run -d emulator-5554 --dart-define=API_URL=$(API_URL_DEV)

debug-ios-device: ios-sign
	flutter run -d $(DEVICE) --dart-define=API_URL=$(API_URL_DEV)

ios-device: ios-sign
	flutter run -d $(DEVICE) --dart-define=API_URL=$(API_URL_PROD)

android-device:
	flutter run -d ${DEVICE} --dart-define=API_URL=$(API_URL_PROD)

# ============================================================================
# Development/Debug Targets
# ============================================================================

debug:
	$(MAKE) -j3 build-and-run-ios build-and-run build-and-run-android

# ============================================================================
# Testing & Linting Targets
# ============================================================================

lint:
	flutter analyze

test:
	flutter test

format:
	dart format .

# ============================================================================
# Cleanup Targets
# ============================================================================

clean:
	flutter clean
