# Flock Map App (Stage 1)

A minimal Flutter scaffold for mapping and tagging Flock‑style ALPR cameras in OpenStreetMap.

# OAuth Setup

Before you can upload to OpenStreetMap (production **or sandbox**), you must register your own OAuth2 application on each OSM API you wish to support:
- [Production OSM register page](https://www.openstreetmap.org/oauth2/applications)
- [Sandbox OSM register page](https://master.apis.dev.openstreetmap.org/oauth2/applications)

Copy your generated client IDs into a new file:

```dart
// lib/keys.dart
const String kOsmProdClientId = 'YOUR_PROD_CLIENT_ID_HERE';
const String kOsmSandboxClientId = 'YOUR_SANDBOX_CLIENT_ID_HERE';
```

For open source: use `lib/keys.dart.example` as a template and do **not** commit your real secrets.

If you discover a bug that causes bad behavior w/rt OSM API, register a new OAuth client to distinguish patched versions and, if needed, delete the old app to prevent misuse.

# Upload Modes

In Settings, you can now choose your "Upload Destination":
- **Production**: Live OSM database (visible to all users).
- **Sandbox**: OSM's dedicated test database; safe for development/testing. [More info](https://wiki.openstreetmap.org/wiki/Sandbox).
- **Simulate**: Does not contact any server. Actions are fully offline for testing UI/flows.

---

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
- Direction should be optional actually (for things like gunshot detectors) - maybe a profile setting?
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
