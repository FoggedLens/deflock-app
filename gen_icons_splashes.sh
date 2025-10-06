#!/bin/bash

echo "Generate icons..."
dart run flutter_launcher_icons
echo
echo
echo "Generate splash screens..."
dart run flutter_native_splash:create
