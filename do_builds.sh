#!/bin/bash

# Default options
BUILD_IOS=true
BUILD_ANDROID=true

# Function to read key=value from file
read_from_file() {
  local key="$1"
  local file="build_keys.conf"
  
  if [ ! -f "$file" ]; then
    return 1
  fi
  
  # Read key=value pairs, ignoring comments and empty lines
  while IFS='=' read -r k v; do
    # Skip comments and empty lines
    if [[ "$k" =~ ^[[:space:]]*# ]] || [[ -z "$k" ]]; then
      continue
    fi
    
    # Remove leading/trailing whitespace
    k=$(echo "$k" | xargs)
    v=$(echo "$v" | xargs)
    
    if [ "$k" = "$key" ]; then
      echo "$v"
      return 0
    fi
  done < "$file"
  
  return 1
}

# Parse arguments
for arg in "$@"; do
  case $arg in
    --ios)
      BUILD_ANDROID=false
      ;;
    --android)
      BUILD_IOS=false
      ;;
    *)
      echo "Usage: $0 [--ios | --android]"
      echo "  --ios       Build only iOS"
      echo "  --android   Build only Android"
      echo "  (default builds both)"
      echo ""
      echo "OSM client IDs must be configured in build_keys.conf"
      echo "See build_keys.conf.example for format"
      exit 1
      ;;
  esac
done

# Load client IDs from build_keys.conf
if [ ! -f "build_keys.conf" ]; then
  echo "Error: build_keys.conf not found"
  echo "Copy build_keys.conf.example to build_keys.conf and fill in your OSM client IDs"
  exit 1
fi

echo "Loading OSM client IDs from build_keys.conf..."
OSM_PROD_CLIENTID=$(read_from_file "OSM_PROD_CLIENTID")
OSM_SANDBOX_CLIENTID=$(read_from_file "OSM_SANDBOX_CLIENTID")

# Check required keys
if [ -z "$OSM_PROD_CLIENTID" ]; then
  echo "Error: OSM_PROD_CLIENTID not found in build_keys.conf"
  exit 1
fi

if [ -z "$OSM_SANDBOX_CLIENTID" ]; then
  echo "Error: OSM_SANDBOX_CLIENTID not found in build_keys.conf"
  exit 1
fi

# Build the dart-define arguments
DART_DEFINE_ARGS="--dart-define=OSM_PROD_CLIENTID=$OSM_PROD_CLIENTID --dart-define=OSM_SANDBOX_CLIENTID=$OSM_SANDBOX_CLIENTID"

# Validate localizations before building
echo "Validating localizations..."
dart run scripts/validate_localizations.dart || exit 1
echo

appver=$(grep "version:" pubspec.yaml | head -1 | cut -d ':' -f 2 | tr -d ' ' | cut -d '+' -f 1)
echo
echo "Building app version ${appver}..."
echo

if [ "$BUILD_IOS" = true ]; then
  echo "Building iOS..."
  flutter build ios --no-codesign $DART_DEFINE_ARGS || exit 1

  echo "Converting .app to .ipa..."
  ./app2ipa.sh build/ios/iphoneos/Runner.app || exit 1

  echo "Moving iOS files..."
  mv Runner.ipa "../deflock_v${appver}.ipa" || exit 1
  echo
fi

if [ "$BUILD_ANDROID" = true ]; then
  echo "Building Android..."
  flutter build apk $DART_DEFINE_ARGS || exit 1

  echo "Moving Android files..."
  cp build/app/outputs/flutter-apk/app-release.apk "../deflock_v${appver}.apk" || exit 1
  echo
fi

echo "Done."

