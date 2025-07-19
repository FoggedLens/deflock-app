#!/bin/bash

# Check if an argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <path_to_your_app.app>"
    exit 1
fi

APP_PATH="$1"
APP_NAME=$(basename "$APP_PATH" .app) # Extract app name without .app extension

# 1. Create a Payload directory
PAYLOAD_DIR="Payload"
mkdir -p "$PAYLOAD_DIR"

# 2. Move the .app bundle inside the Payload directory
cp -r "$APP_PATH" "$PAYLOAD_DIR/"

# 3. Create the .ipa by zipping the Payload directory and renaming
zip -r "$APP_NAME.zip" "$PAYLOAD_DIR"
mv "$APP_NAME.zip" "$APP_NAME.ipa"

# 4. Clean up the temporary Payload directory
rm -rf "$PAYLOAD_DIR"

echo "Successfully converted $APP_PATH to $APP_NAME.ipa"

