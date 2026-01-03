.PHONY: web web-release ios-sign ios ipa appbundle run run-ios build-and-run build-and-run-ios build-and-run-android debug debug-ios-device ios-device android-device clean lint test format beta beta-patch beta-minor beta-major release release-patch release-minor release-major

# Load local config (API URLs, device name, etc.)
-include .env.mk

# ============================================================================
# Build Targets
# ============================================================================

# Common dart-define flags
DART_DEFINES_PROD=--dart-define=API_URL=$(API_URL_PROD) --dart-define=WEB_PUSH_CERTIFICATE_KEY_PAIR=$(WEB_PUSH_CERTIFICATE_PAIR)
DART_DEFINES_DEV=--dart-define=API_URL=$(API_URL_DEV) --dart-define=WEB_PUSH_CERTIFICATE_KEY_PAIR=$(WEB_PUSH_CERTIFICATE_PAIR)

web:
	flutter build web $(DART_DEFINES_DEV)

web-release:
	flutter build web --release $(DART_DEFINES_PROD)

ios-sign:
	flutter build ios $(DART_DEFINES_DEV)

ios:
	flutter build ios --no-codesign $(DART_DEFINES_DEV)

ipa:
	flutter build ipa --release $(DART_DEFINES_PROD)
	xcrun iTMSTransporter -m upload -assetFile build/ios/ipa/*.ipa -apiKey $(APP_STORE_API_KEY) -apiIssuer $(APP_STORE_ISSUER_ID)

appbundle:
	flutter build appbundle --release $(DART_DEFINES_PROD)

# ============================================================================
# Run Targets
# ============================================================================

run:
	flutter run -d chrome --web-port=8090 $(DART_DEFINES_DEV)

run-ios:
	flutter run -d iPhone $(DART_DEFINES_DEV)

build-and-run: web
	$(MAKE) run

build-and-run-ios: ios
	$(MAKE) run-ios

build-and-run-android:
	flutter run -d emulator-5554 $(DART_DEFINES_DEV)

debug-ios-device: ios-sign
	flutter run -d $(DEVICE) $(DART_DEFINES_DEV)

ios-device: ios-sign
	flutter run -d $(DEVICE) $(DART_DEFINES_PROD)

android-device:
	flutter run -d ${DEVICE} $(DART_DEFINES_PROD)

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
# Fastlane Targets
# ============================================================================

beta:
	cd ios && bundle exec fastlane beta github_release:true

beta-patch:
	cd ios && bundle exec fastlane beta bump:patch github_release:true

beta-minor:
	cd ios && bundle exec fastlane beta bump:minor github_release:true

beta-major:
	cd ios && bundle exec fastlane beta bump:major github_release:true

release:
	cd ios && bundle exec fastlane release github_release:true

release-patch:
	cd ios && bundle exec fastlane release bump:patch github_release:true

release-minor:
	cd ios && bundle exec fastlane release bump:minor github_release:true

release-major:
	cd ios && bundle exec fastlane release bump:major github_release:true

# ============================================================================
# Cleanup Targets
# ============================================================================

clean:
	flutter clean
