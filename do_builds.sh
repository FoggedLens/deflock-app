#!/bin/bash

appver=$(cat lib/dev_config.dart | grep "kClientVersion" | cut -d '=' -f 2 | tr -d ';' | tr -d "\'" | tr -d " ")
echo
echo "Building app version ${appver}..."
flutter build ios --no-codesign
flutter build apk
echo
echo "Converting .app to .ipa..."
./app2ipa.sh build/ios/iphoneos/Runner.app
echo
echo "Moving files..."
cp build/app/outputs/flutter-apk/app-release.apk ../flockmap_v${appver}.apk
mv Runner.ipa ../flockmap_v${appver}.ipa
echo
echo "Done."
