.PHONY: web web-release ios-sign ios run run-ios clean all debug build-and-run build-and-run-ios debug-device

# Load local config (API URLs, device name, etc.)
-include .env.mk

web:
	flutter build web

web-release:
	flutter build web --release

ios-sign:
	flutter build ios

ios:
	flutter build ios --no-codesign

run:
	flutter run -d chrome --web-port=8090

run-ios:
	flutter run -d iPhone

build-and-run: web
	$(MAKE) run

build-and-run-ios: ios
	$(MAKE) run-ios

all:
	$(MAKE) -j2 ios web

debug:
	$(MAKE) -j2 build-and-run-ios build-and-run

clean:
	flutter clean

lint:
	flutter analyze

test:
	flutter test

debug-device: ios-sign
	flutter run -d $(DEVICE) --dart-define=API_URL=$(API_URL_DEV)

device: ios-sign
	flutter run -d $(DEVICE) --dart-define=API_URL=$(API_URL_PROD)

ipa:
	flutter build ipa --release --dart-define=API_URL=$(API_URL_PROD)
