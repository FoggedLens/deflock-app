#!/bin/bash

echo "Generate splash screens..."
flutter pub run flutter_native_splash:create
echo
echo
echo "Generate icons..."
flutter pub run flutter_launcher_icons:main
