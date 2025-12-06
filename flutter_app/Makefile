.PHONY: web web-release ios-sign ios run run-ios clean all debug build-and-run build-and-run-ios

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
	flutter run -d chrome

build-and-run-ios: ios
	flutter run -d iPhone

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