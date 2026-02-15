# ============================================================================
# DeFlock App — Build Orchestration
# ============================================================================
#
# This Makefile ensures generated assets (icons, splash screens) are always
# built before any Flutter build target. It uses file-timestamp tracking so
# repeated runs skip work that's already done.
#
# Quick reference:
#   make              — run analyze + test  (the default)
#   make all          — build debug APK + iOS simulator app
#   make help         — list every target with descriptions
#
# NOTE: Indentation in Makefiles MUST be tabs, not spaces.
# ============================================================================

.DEFAULT_GOAL := check

# Stop partial outputs from surviving a failed recipe.
.DELETE_ON_ERROR:

# ──── Variables ────────────────────────────────────────────────────────────
# Build output paths — used as file targets so Make can skip fresh builds.

APK_DEBUG    := build/app/outputs/flutter-apk/app-debug.apk
APK_RELEASE  := build/app/outputs/flutter-apk/app-release.apk
AAB_RELEASE  := build/app/outputs/bundle/release/app-release.aab
IOS_SIM_APP  := build/ios/iphonesimulator/Runner.app/Info.plist

# Inputs that should trigger asset regeneration when changed.
ASSET_SOURCES := pubspec.yaml assets/app_icon.png assets/android_app_icon.png assets/transparent_1x1.png

# CI can pass extra flags (e.g. --dart-define) via this variable.
# Example: make release-apk FLUTTER_BUILD_ARGS="--dart-define=OSM_PROD_CLIENTID=..."
FLUTTER_BUILD_ARGS ?=

# ──── Dependency checks ────────────────────────────────────────────────────
# Verify required tools are installed before building.
# Runs once per clean checkout (tracked by stamp file).

.stamps/check-deps:
	@echo "Checking build dependencies..."
	@command -v flutter >/dev/null || (echo "ERROR: flutter not found. Install: brew install --cask flutter" && exit 1)
	@command -v dart >/dev/null    || (echo "ERROR: dart not found. Install: brew install --cask flutter" && exit 1)
	@mkdir -p .stamps && touch $@

.stamps/check-android-deps: .stamps/check-deps
	@command -v java >/dev/null || (echo "ERROR: java not found. Install: brew install --cask temurin" && exit 1)
	@touch $@

.stamps/check-ios-deps: .stamps/check-deps
	@command -v pod >/dev/null || (echo "ERROR: cocoapods not found. Install: brew install cocoapods" && exit 1)
	@touch $@

# ──── File targets (dependency-tracked) ────────────────────────────────────
# Stamp files in .stamps/ record "this step completed at this time". Make
# compares their timestamps against prerequisites to decide whether to re-run.
# We use stamps because these steps produce many scattered output files
# (e.g. icon generation writes ~20 PNGs across android/ and ios/).

.stamps/pub-get: .stamps/check-deps pubspec.yaml pubspec.lock
	flutter pub get
	@mkdir -p .stamps && touch $@

.stamps/generate-assets: .stamps/pub-get $(ASSET_SOURCES)
	dart run flutter_launcher_icons
	dart run flutter_native_splash:create
	@touch $@

$(APK_DEBUG): .stamps/generate-assets .stamps/check-android-deps
	flutter build apk --debug

$(IOS_SIM_APP): .stamps/generate-assets .stamps/check-ios-deps
	flutter build ios --debug --simulator

$(APK_RELEASE): .stamps/generate-assets .stamps/check-android-deps
	flutter build apk --release $(FLUTTER_BUILD_ARGS)

$(AAB_RELEASE): .stamps/generate-assets .stamps/check-android-deps
	flutter build appbundle $(FLUTTER_BUILD_ARGS)

# IPA output filename varies by version — use stamp instead of file target.
.stamps/release-ios: .stamps/generate-assets .stamps/check-ios-deps
	flutter build ipa --release --export-options-plist=ios/exportOptions.plist $(FLUTTER_BUILD_ARGS)
	@touch $@

# ──── Phony targets ────────────────────────────────────────────────────────
# These targets don't produce a file with their name, so Make should always
# run their recipes. Everything else uses real file targets above.

.PHONY: all check analyze test ci clean help version \
        generate-assets pub-get \
        build-apk-debug build-ios-simulator \
        release release-apk release-aab release-ios

# Default: validate code (bare `make` runs this).
check: analyze test

# Build all debug binaries (iOS targets require macOS).
all: build-apk-debug build-ios-simulator

analyze: .stamps/pub-get
	flutter analyze

test: .stamps/pub-get
	flutter test

# CI validation — what the PR workflow runs.
ci: check

# ──── Convenience aliases ──────────────────────────────────────────────────
# Human-friendly names that delegate to the file targets above.

generate-assets: .stamps/generate-assets
pub-get: .stamps/pub-get
build-apk-debug: $(APK_DEBUG)
build-ios-simulator: $(IOS_SIM_APP)
release-apk: $(APK_RELEASE)
release-aab: $(AAB_RELEASE)
release-ios: .stamps/release-ios
release: release-apk release-aab release-ios

version:
	@grep "version:" pubspec.yaml | head -1 | cut -d ':' -f 2 | tr -d ' ' | cut -d '+' -f 1

clean:
	flutter clean
	rm -rf .stamps
	rm -rf android/app/src/main/res/drawable*/
	rm -rf android/app/src/main/res/mipmap*/
	rm -f ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png
	rm -f ios/Runner/Assets.xcassets/LaunchImage.imageset/*.png
	rm -f ios/Runner/Assets.xcassets/LaunchBackground.imageset/*.png

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Development (default: check)"
	@echo "  check              Run analyze + test"
	@echo "  analyze            Run flutter analyze"
	@echo "  test               Run flutter test"
	@echo "  generate-assets    Generate app icons and splash screens"
	@echo "  pub-get            Install Flutter dependencies"
	@echo ""
	@echo "Debug builds"
	@echo "  all                Build all debug binaries (iOS requires macOS)"
	@echo "  build-apk-debug    Build debug APK"
	@echo "  build-ios-simulator Build iOS simulator app"
	@echo ""
	@echo "Release builds (require signing config)"
	@echo "  release            Build all release binaries"
	@echo "  release-apk        Build release APK"
	@echo "  release-aab        Build release AAB (Play Store)"
	@echo "  release-ios        Build release IPA (App Store)"
	@echo ""
	@echo "Housekeeping"
	@echo "  clean              Remove all build outputs and generated assets"
	@echo "  version            Print app version from pubspec.yaml"
	@echo "  help               Show this help"
