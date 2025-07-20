# Flock Map App (Stage 1)

A minimal Flutter scaffold for mapping and tagging Flock‑style ALPR cameras in OpenStreetMap.

# NOTE:
Forks should register for their own oauth2 client id from OSM: https://www.openstreetmap.org/oauth2/applications
These are hardcoded in lib/services/auth_service.dart for each app.
If you discover a bug that causes bad behavior w/rt OSM API, you might want to register a new one for the patched version to distinguish them. You can also then delete the old version from OSM to prevent new people from using the old version.

## TODO for Beta/RC Release

### COMPLETED
- Queue view/retry/clear - Implemented with test mode support
- Fix login not opening browser - Fixed OAuth scope and client ID issues
- Add "new profile" text to button in settings - Enhanced profile management UI
- Profile management (create/edit/delete) - Full CRUD operations integrated

### 🔄 REMAINING FOR BETA/RC
- Better icons for cameras, prettier/wider FOV cones
- North up mode, satellite view mode  
- Error handling when clicking "add camera" but no profiles enabled
- Camera point details popup (tap to view full details, edit if user-submitted)
- One-time popup about "this app trusts the user to know what they are doing" + credits/attributions
- Optional height tag for cameras
- More (unspecified items)

### FUTURE (Post-Beta)
- Wayfinding to avoid cameras

## Stuff for build env
# Install from GUI:
Xcode, Android Studio.
Xcode cmdline tools
Android cmdline tools + NDK

# Terminal
brew install openjdk@17
sudo ln -sfn /usr/local/opt/openjdk@17/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk.jdk

brew install ruby

gem install cocoapods

sdkmanager --install "ndk;27.0.12077973"

export PATH="/Users/bob/.gem/ruby/3.4.0/bin:$PATH"

export PATH=$HOME/development/flutter/bin:$PATH

flutter clean
flutter pub get
flutter run
