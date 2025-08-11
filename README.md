# Flock Map App

A Flutter app for mapping and tagging ALPR-style cameras (and other surveillance nodes) for OpenStreetMap, with advanced offline support, robust camera profile management, and a pro-grade UX.

---

## Code Organization (2025 Refactor)

- **Data providers:** All map tile and camera data fetching now routes through `lib/services/map_data_provider.dart`, which supports both OSM/Overpass and fully offline/local sources, with pluggable submodules:
  - Remote tile fetch: `map_data_submodules/tiles_from_osm.dart`
  - Remote cameras: `map_data_submodules/cameras_from_overpass.dart`
  - *Coming soon:* Local tile/camera modules for offline/area-aware access
- **Settings UI:** Each settings section lives in its own widget under `lib/screens/settings_screen_sections/`, using clean, modular ListTile-based layouts.
- **Offline areas:** Management, persistence, and download logic remain in `OfflineAreaService`, but all fetch/caching is routed through the new provider.
- **Legacy OSM/Overpass tile and camera fetch code has been removed from old modules.**

---

## Key Features

### Map Data & Provider Architecture
- **All map tile and camera fetches** go through MapDataProvider, which selects local or remote sources as needed, automatically obeying the user's offline/online preference and settings.
- **Offline Mode:** A global toggle in Settings disables all remote network fetches, forcing the app to use only locally downloaded map areas and cached camera data. (Instant feedback; no network calls when enabled.)
- **MapSource Selection:** MapDataProvider lets calling code specify local-only, remote-only, or auto preference for tiles and camera points.

### Map View
- **Seamless offline/online tile loading:** Tiles are fetched (in parallel, with global concurrency/throttle control and exponential backoff) from OSM *only as needed*, with robust error handling and UI updates as tiles arrive.
- **Camera overlays** are fetched from Overpass or local cache, respecting both offline mode and user preference for which camera types to display.

### Camera Profiles & Upload Queue
- Unchanged: creation/editing/enabling; see prior documentation.

### Offline Map Areas
- **Download tiles/cameras for any bounding box**; areas cover any region/zoom, and are automatically de-duped and managed.
- **Robust area downloads** use the same MapDataProvider for source-of-truth logic, so downloads are always consistent with runtime lookup.
- **Permanent world base map** at low zoom always available for core map functionality, even on first-use/offline.

### Modular, Future-friendly Codebase
- **No network fetch code outside the provider and submodules.**
- **All legacy/duplicate OSM/Overpass downloaders have been removed or marked for deprecation.**

---

## For Developers

**Highlights:**
- To add a new data source, just drop in a new submodule and route fetch via MapDataProvider.
- Any section of the app that needs tiles or camera data calls MapDataProvider with the relevant bounds/zoom/profiles and source preference.
- Offline Mode and all core settings are strictly respected at a single data/control point.

---

## Roadmap (2025+)

- **COMPLETE:** Core provider logic, settings, robust downloading and modular prefetch/caching.
- **IN PROGRESS:** Local/offline tile/camera fetch modules for runtime map viewing and offline area management.
- **NEXT:** More map overlays, offline routing, and data visualization.
- **SOON:** UX polish for download/error states, multi-layer base maps.

---

*See prior README version for detailed setup/build/dependency notes—they remain unchanged!*


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
- **Intelligent Tile Management:** World tiles at zooms 1–4 are permanently available (via a protected offline area). All downloads include accurate tile and storage estimates, and never request duplicate or unnecessary tiles.
- **Robust Downloading:** All tile/download logic uses serial fetching and exponential backoff for network failures, minimizing risk of OSM rate-limits and always respecting API etiquette.
- **No Duplicates:** Only one world area; can be re-downloaded (refreshed) but never deleted or renamed.
- **Camera Cache:** Download areas keep camera points in sync for full offline visibility—except the global area, which never attempts to fetch all world cameras.
- **Settings Management:** Cancel, refresh, or remove downloads as needed. Progress, tile count, storage consumption, and cached camera count always displayed.

### Polished UX & Settings Architecture
- **Permanent global base map:** Coverage for the entire world at zooms 1–4, always present.
- **Smooth map gestures:** Double-tap to zoom even on markers; pinch zoom; camera popups distinguished from zoom.
- **Modular Settings:** All major settings/queue/offline/camera management UI sections are cleanly separated for extensibility and rapid development.
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
  - Offline map area download/storage/camera overlay; cancel/retry; fast tile/camera/size estimates; exponential backoff and robust retry logic for network outages or rate-limiting.
  - Pro-grade map UX (zoom bar, marker tap/double-tap, robust FABs).
  - Modularized, maintainable codebase using small service/helper files and section-separated UI components.
- **SOON**:  
  - "Offline mode" setting: map never hits the network and always provides a fallback tile for every view (no blank maps; graceful offline-first UX).
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
