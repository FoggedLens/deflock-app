# DeFlock

A comprehensive Flutter app for mapping public surveillance infrastructure with OpenStreetMap. Includes offline capabilities, editing ability, and an intuitive interface.

**DeFlock** is a privacy-focused initiative to document the rapid expansion of ALPRs, AI surveillance cameras, and other public surveillance infrastructure. This app aims to be the go-to tool for contributors to map surveillance devices in their communities and upload the data to OpenStreetMap, making surveillance infrastructure visible and searchable.

**For complete documentation, tutorials, and community info, visit [deflock.me](https://deflock.me)**

---

## What This App Does

- **Map surveillance infrastructure** including cameras, ALPRs, gunshot detectors, and more with precise location, direction, and manufacturer details
- **Upload to OpenStreetMap** with OAuth2 integration (live or sandbox modes)
- **Work completely offline** with downloadable map areas and device data, plus upload queue
- **Multiple map types** including satellite imagery from Google, Esri, Mapbox, and OpenStreetMap, plus custom map tile provider support
- **Editing Ability** to update existing device locations and properties
- **Built-in device profiles** for Flock Safety, Motorola, Genetec, Leonardo, and other major manufacturers, plus custom profiles for more specific tag sets

---

## Key Features

### Map & Navigation
- **Multi-source tiles**: Switch between OpenStreetMap, Google Satellite, Esri imagery, Mapbox, and any custom providers
- **Offline-first design**: Download a region for complete offline operation
- **Smooth UX**: Intuitive controls, follow-me mode with GPS rotation, and gesture-friendly interactions
- **Device visualization**: Color-coded markers showing real devices (blue), pending uploads (purple), new devices (white), edited devices (grey), and devices being edited (orange)

### Device Management
- **Comprehensive profiles**: Built-in profiles for major manufacturers (Flock Safety, Motorola/Vigilant, Genetec, Leonardo/ELSAG, Neology) plus custom profile creation
- **Editing capabilities**: Update location, direction, and tags of existing devices
- **Direction visualization**: Interactive field-of-view cones showing camera viewing angles
- **Bulk operations**: Tag multiple devices efficiently with profile-based workflow

### Professional Upload & Sync
- **OpenStreetMap integration**: Direct upload with full OAuth2 authentication
- **Upload modes**: Production OSM, testing sandbox, or simulate-only mode
- **Queue management**: Review, edit, retry, or cancel pending uploads
- **Changeset tracking**: Automatic grouping and commenting for organized contributions

### Offline Operations
- **Smart area downloads**: Automatically calculate tile counts and storage requirements
- **Device caching**: Offline areas include surveillance device data for complete functionality without network
- **Global base map**: Permanent worldwide coverage at low zoom levels
- **Robust downloads**: Exponential backoff, retry logic, and progress tracking for reliable area downloads

---

## Quick Start

1. **Install** the app on iOS or Android
2. **Enable location** permissions  
3. **Log into OpenStreetMap**: Choose upload mode and get OAuth2 credentials
4. **Add your first device**: Tap the "tag node" button, position the pin, set direction, select a profile, and tap submit

**New to OpenStreetMap?** Visit [deflock.me](https://deflock.me) for complete setup instructions and community guidelines.

---

## For Developers

### Architecture Highlights
- **Unified data provider**: All map tiles and surveillance device data route through `MapDataProvider` with pluggable remote/local sources
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

### v1 todo/bug List
- Update offline area nodes while browsing?
- Camera deletions
- Optional custom icons for camera profiles
- Upgrade device marker design (considering nullplate's svg)

### Future Features & Wishlist
- Jump to location by coordinates, address, or POI name
- Route planning that avoids surveillance devices (alprwatch.com/directions)
- Suspected locations toggle (alprwatch.com/flock/utilities)
- Location-based notifications when approaching surveillance devices
- Red/yellow ring for devices missing specific tag details
- "Cache accumulating" offline area?
- "Offline areas" as tile provider?
- Custom device providers and OSM/Overpass alternatives

---

## Contributing & Community

This app is part of the larger **DeFlock** initiative. Join the community:

- **Documentation & Guides**: [deflock.me](https://deflock.me)
- **Community Discussion**: [deflock.me](https://deflock.me)
- **Issues & Feature Requests**: GitHub Issues
- **Development**: See developer setup above

---

## Privacy & Ethics

This project helps make existing public surveillance infrastructure transparent and searchable. We only document surveillance devices that are already installed and visible in public spaces.

No user information is ever collected, and no data leaves your device except submissions to OSM and whatever data your tile provider can glean from your requests.

---

## License

This project is open source. See [LICENSE](LICENSE) for details.
