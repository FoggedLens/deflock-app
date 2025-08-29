# Flock Map App

A comprehensive Flutter app for viewing and mapping surveillance cameras with OpenStreetMap. Includes offline capabilities, editing ability, and an intuitive interface.

**Stop Flock** is a privacy-focused initiative to document the rapid expansion of ALPRs and AI surveillance cameras. This app aims to be the go-to tool for contributors to map cameras in their communities and upload the data to OpenStreetMap, making surveillance infrastructure visible and searchable.

**For complete documentation, tutorials, and community info, visit [stopflock.com/app](https://stopflock.com/app)**

---

## What This App Does

- **Map surveillance cameras** with precise location, direction, and manufacturer details
- **Upload to OpenStreetMap** with OAuth2 integration (live or sandbox modes)
- **Work completely offline** with downloadable map areas and camera data, plus upload queue
- **Multiple map types** including satellite imagery from Google, Esri, Mapbox, and OpenStreetMap, plus custom map tile provider support
- **Editing Ability** to update existing camera locations and properties
- **Built-in camera profiles** for Flock Safety, Motorola, Genetec, Leonardo, and other major manufacturers, plus custom profiles for more specific tag sets

---

## Key Features

### Map & Navigation
- **Multi-source tiles**: Switch between OpenStreetMap, Google Satellite, Esri imagery, Mapbox, and any custom providers
- **Offline-first design**: Download a region for complete offline operation
- **Smooth UX**: Intuitive controls, follow-me mode with GPS rotation, and gesture-friendly interactions
- **Camera visualization**: Color-coded markers showing real cameras (blue), pending uploads (purple), new cameras (white), edited cameras (grey), and cameras being edited (orange)

### Camera Management
- **Comprehensive profiles**: Built-in profiles for major manufacturers (Flock, Motorola/Vigilant, Genetec, Leonardo/ELSAG, Neology) plus custom profile creation
- **Editing capabilities**: Update location, direction, and tags of existing cameras
- **Direction visualization**: Interactive field-of-view cones showing camera viewing angles
- **Bulk operations**: Tag multiple cameras efficiently with profile-based workflow

### Professional Upload & Sync
- **OpenStreetMap integration**: Direct upload with full OAuth2 authentication
- **Upload modes**: Production OSM, testing sandbox, or simulate-only mode
- **Queue management**: Review, edit, retry, or cancel pending uploads
- **Changeset tracking**: Automatic grouping and commenting for organized contributions

### Offline Operations
- **Smart area downloads**: Automatically calculate tile counts and storage requirements
- **Camera caching**: Offline areas include camera data for complete functionality without network
- **Global base map**: Permanent worldwide coverage at low zoom levels
- **Robust downloads**: Exponential backoff, retry logic, and progress tracking for reliable area downloads

---

## Quick Start

1. **Install** the app on iOS or Android
2. **Enable location** and grant camera permissions  
3. **Log into OpenStreetMap**: Choose upload mode and get OAuth2 credentials
4. **Add your first camera**: Tap the "tag camera" button, position the pin, set direction, select a profile, and tap submit

**New to OpenStreetMap?** Visit [stopflock.com/app](https://stopflock.com/app) for complete setup instructions and community guidelines.

---

## For Developers

### Architecture Highlights
- **Unified data provider**: All map tiles and camera data route through `MapDataProvider` with pluggable remote/local sources
- **Modular settings**: Each settings section is a separate widget for maintainability
- **State management**: Provider pattern with clean separation of concerns
- **Offline-first**: Network calls are optional; app functions fully offline with downloaded data and queues uploads until online

### Build Setup
**Prerequisites**: Flutter SDK, Xcode (iOS), Android Studio  
**OAuth Setup**: Register apps at [openstreetmap.org/oauth2](https://www.openstreetmap.org/oauth2/applications) and [OSM Sandbox](https://master.apis.dev.openstreetmap.org/oauth2/applications) to get a client ID

```shell
# Basic setup
flutter pub get
cp lib/keys.dart.example lib/keys.dart
# Add your OAuth2 client IDs to keys.dart

# iOS additional setup
cd ios && pod install

# Run
flutter run
```

---

## Roadmap

### Current Todo List
- **UX Polish**: 
  - Fix "tiles loaded" indicator accuracy across different providers
  - Generic tile provider error messages (not always "OSM tiles slow")
  - Optional custom icons for camera profiles
  - Camera deletions
  - Direction requirement specified by profile; support shotspotter/raven
- **Data Management**:
  - Clean up cache when submitted changesets appear in Overpass results
- **Visual Improvements**:
  - Upgrade camera marker design (considering nullplate's svg)

### Future Features & Wishlist
- **Operator Profiles**:
  - Additional tag sets for different surveillance operators
- **Announcement Mode**:
  - Location-based notifications when approaching cameras
- **Enhanced Visualizations**:
  - Red/yellow ring for cameras missing specific tag details
  - iOS/Android native themes and dark mode support
- **Advanced Offline**:
  - "Cache accumulating" offline areas with size estimates per area
  - "Offline areas" as tile provider?
- **Navigation & Search**:
  - Jump to location by coordinates, address, or POI name
  - Route planning that avoids surveillance cameras
- **Data Sources**:
  - Custom camera providers and OSM/Overpass alternatives

---

## Contributing & Community

This app is part of the larger **Stop Flock** initiative. Join the community:

- **Documentation & Guides**: [stopflock.com/app](https://stopflock.com/app)
- **Community Discussion**: [stopflock.com](https://stopflock.com)
- **Issues & Feature Requests**: GitHub Issues
- **Development**: See developer setup above

---

## Privacy & Ethics

This project helps make existing public surveillance infrastructure transparent and searchable. We only document cameras that are already installed and visible in public spaces.

No user information is ever collected, and no data leaves your device except submissions to OSM and whatever data your tile provider can glean from your requests.

---

## License

This project is open source. See [LICENSE](LICENSE) for details.
