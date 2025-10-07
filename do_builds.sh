#!/bin/bash

# Default options
BUILD_IOS=true
BUILD_ANDROID=true

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
      exit 1
      ;;
  esac
done

appver=$(grep "version:" pubspec.yaml | head -1 | cut -d ':' -f 2 | tr -d ' ' | cut -d '+' -f 1)
echo
echo "Building app version ${appver}..."
echo

if [ "$BUILD_IOS" = true ]; then
  echo "Building iOS..."
  flutter build ios --no-codesign || exit 1

  echo "Converting .app to .ipa..."
  ./app2ipa.sh build/ios/iphoneos/Runner.app || exit 1

  echo "Moving iOS files..."
  mv Runner.ipa "../deflock_v${appver}.ipa" || exit 1
  echo
fi

if [ "$BUILD_ANDROID" = true ]; then
  echo "Building Android..."
  flutter build apk || exit 1

  echo "Moving Android files..."
  cp build/app/outputs/flutter-apk/app-release.apk "../deflock_v${appver}.apk" || exit 1
  echo
fi

echo "Done."

