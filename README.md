# Flock Map App

A Flutter app for mapping and tagging ALPR-style cameras (and other surveillance nodes) for OpenStreetMap. Recently expanded with robust profile and upload management, and now with in-progress OFFLINE MAP AREA support.

# User Experience

## Map View
- View OSM map with online tiles and camera overlays.
- Main actions: "Tag Camera" to add a node; "Download" to save an offline map area (in progress).

## Camera Tagging & Profiles
- Add cameras by dropping a pin, setting direction/angle, and selecting a camera profile.
- Manage camera profiles in Settings: create, edit, delete, and enable/disable for tagging.

## Upload Destinations
- Select from Production OSM, OSM Sandbox, or Simulate (offline/test) in Settings.
- Upload queue visible in Settings, with clear/retry.
- Full OAuth flow for user authentication to OSM.

## Offline Areas *(IN PROGRESS)*
- Download any map area for offline use! Uses OSM raster tile cache and Overpass-surveillance cameras.
- Each area download:
  - Selects the current map region with a dynamic minimum zoom (calculated as the highest zoom level at which a single tile covers the selected area)
  - Lets user pick the max zoom, shows real tile/storage estimate.
  - Always includes world tiles for zoom 1–4 for seamless context.
  - Downloads **all** camera points in area (not just top 250) for offline visibility.
- Status, progress, and detailed area management appear in Settings:
  - Cancel, retry, and delete areas (in UI now)
  - Storage/camera breakdown per area (coming soon)

---


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

## Roadmap and Progress (Beta, Summer–Fall 2025)

### **COMPLETE**
- Full queue management: view/cancel/retry/clear all uploads (incl. simulated/test modes)
- OAuth and upload destination management (choose prod, sandbox, offline/sim)
- Flexible profile system for cameras (full CRUD, enable/disable, per-camera tagging)
- Polished map experience: fixed FAB UX, dialogs, overlays

### **IN PROGRESS – OFFLINE MAP AREAS**
- Dynamic min-zoom and tile/storage estimate in the Download dialog
- Settings: new section listing offline areas with progress, camera count, and management (delete/cancel)
- Tiles for world zooms 1-4 always included for context
- Backend downloads all camera points in area for full offline mapping (already working)
- Area downloads correctly resumed/cancelled (UI feedback working)
- **NEXT:**
    - Persist area index/restores after restart
    - Tile loading from disk (offline-viewable map)
    - True offline/cached camera overlays
    - Polished error/retry flow & final UX fit & finish

### **REMAINING/LATER**
- Fancier camera tag/cone icons
- Satellite/North-up map options
- Settings polish, more informative error/credits flow
- Misc polish, final bugfixes
- Future: post-beta/offline wayfinding

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
