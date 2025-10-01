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
- **Device visualization**: Color-coded markers showing real devices (blue), pending uploads (purple), pending edits (grey), devices being edited (orange), and pending deletions (red)

### Device Management
- **Comprehensive profiles**: Built-in profiles for major manufacturers (Flock Safety, Motorola/Vigilant, Genetec, Leonardo/ELSAG, Neology) plus custom profile creation
- **Full CRUD operations**: Create, edit, and delete surveillance devices
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
4. **Add your first device**: Tap the "New Node" button, position the pin, set direction, select a profile, and tap submit
5. **Edit or delete devices**: Tap any device marker to view details, then use Edit or Delete buttons

**New to OpenStreetMap?** Visit [deflock.me](https://deflock.me) for complete setup instructions and community guidelines.

---

## For Developers

**See [DEVELOPER.md](DEVELOPER.md)** for comprehensive technical documentation including:
- Architecture overview and design decisions
- Development setup and build instructions  
- Code organization and contribution guidelines
- Debugging tips and troubleshooting

**Quick setup:**
```shell
flutter pub get
cp lib/keys.dart.example lib/keys.dart
# Add OAuth2 client IDs, then: flutter run
```

---

## Roadmap

### Current Development
- Clean cache when nodes have disappeared / been deleted by others
- Clean up dev_config
- Improve offline area node refresh live display
- Add default operator profiles (Lowe’s etc)

### Future Features & Wishlist
- Update offline area nodes while browsing?
- Suspected locations toggle (alprwatch.com/flock/utilities)
- Jump to location by coordinates, address, or POI name
- Route planning that avoids surveillance devices (alprwatch.com/directions)

### Maybes
- Yellow ring for devices missing specific tag details?
- "Cache accumulating" offline area?
- "Offline areas" as tile provider?
- Optional custom icons for camera profiles?
- Upgrade device marker design? (considering nullplate's svg)
- Custom device providers and OSM/Overpass alternatives?
- More map data providers:
https://gis.sanramon.ca.gov/arcgis_js_api/sdk/jsapi/esri.basemaps-amd.html#osm
https://www.icgc.cat/en/Geoinformation-and-Maps/Base-Map-Service
https://github.com/CartoDB/basemap-styles
https://forum.inductiveautomation.com/t/perspective-map-theming-internet-tile-server-options/40164
https://github.com/roblabs/xyz-raster-sources
https://github.com/geopandas/xyzservices/blob/main/provider_sources/xyzservices-providers.json
https://medium.com/@go2garret/free-basemap-tiles-for-maplibre-18374fab60cb

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
