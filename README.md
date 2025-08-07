# Flock Map App

A Flutter app for mapping and tagging ALPR-style cameras (and other surveillance nodes) for OpenStreetMap, with advanced offline support, robust camera profile management, and a pro-grade UX.

---

## User Experience & Features

### Map View
- **Explore the Map:** View OSM raster tiles, live camera overlays, and a visual scale bar and zoom indicator in the lower left.
- **Tag Cameras:** Add a camera by dropping a pin, setting direction, and choosing a camera profile. Camera tap/double-tap is smart—double-tap always zooms, single-tap opens camera info.
- **Location:** Blue GPS dot shows your current location, always on top of map icons.

### Camera Profiles
- **Flexible, Private Profiles:** Enable/disable, create, edit, or delete camera types in Settings. At least one profile must be enabled at all times.
- If the last enabled profile is disabled, the generic profile will be auto-enabled so the app always works.

### Upload Destinations/Queue
- **Full OSM OAuth2 Integration:** Upload to live OSM, OSM Sandbox for testing, or keep your changes private in simulate mode.
- **Queue Management:** Settings screen shows a queue of pending uploads—clear or retry them as you wish.

### Offline Map Areas
- **Download Any Region, Any Zoom:** Save the current map area at any zoom for true offline viewing.
- **Intelligent Tile Management:** World tiles at zooms 1–4 are permanently available (via a protected offline area). All downloads include accurate tile and storage estimates.
- **No Duplicates:** Only one world area; can be re-downloaded (refreshed) but never deleted or renamed.
- **Camera Cache:** Download areas keep camera points in sync for full offline visibility—except the global area, which never attempts to fetch all world cameras.
- **Settings Management:** Cancel, refresh, or remove downloads as needed. Progress, tile count, storage consumption, and cached camera count always displayed.

### Polished UX Features
- **Permanent global base map:** Coverage for the entire world at zooms 1–4, always present.
- **Smooth map gestures:** Double-tap to zoom even on markers; pinch zoom; camera popups distinguished from zoom.
- **Order-preserving overlays:** Your location is always drawn on top for easy visibility.
- **No more dead ends:** Disabling all profiles is impossible; canceling downloads is clean and instant.

---

## OAuth & Build Setup

**Before uploading to OSM:**
- Register OAuth2 applications on both [Production OSM](https://www.openstreetmap.org/oauth2/applications) and [Sandbox OSM](https://master.apis.dev.openstreetmap.org/oauth2/applications).
- Copy generated client IDs to `lib/keys.dart` (see template `.example` file).

### Build Environment Notes
- Requires Xcode, Android Studio, and standard Flutter dependencies. See notes at the end of this file for CLI setup details.

---

## Roadmap

- **COMPLETE**:  
  - Offline map area download/storage/camera overlay; cancel/retry; fast tile/camera/size estimates.
  - Pro-grade map UX (zoom bar, marker tap/double-tap, robust FABs).
- **SOON**:  
  - Resumable/robust interrupted downloads.
  - Further polish for edge cases (queue, error states).
- **LATER**:
  - Satellite base layers, north-up/satellite-mode.
  - Offline wayfinding or routing.
  - Fancier icons and overlays.

---

## Build Environment Quick Setup

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
