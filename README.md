# DeFlock

A comprehensive Flutter app for mapping public surveillance infrastructure with OpenStreetMap. Includes offline capabilities, editing ability, and an intuitive interface.

**DeFlock** is a privacy-focused initiative to document the rapid expansion of ALPRs, AI surveillance cameras, and other public surveillance infrastructure. This app aims to be the go-to tool for contributors to map surveillance devices in their communities and upload the data to OpenStreetMap, making surveillance infrastructure visible and searchable.

**For complete documentation, tutorials, and community info, visit [deflock.me](https://deflock.me)**

<a href="https://apps.apple.com/us/app/deflock-me/id6752760780" style="display: inline-block;">
<img src="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/en-us?releaseDate=1695859200" alt="Download on the App Store" style="width: 246px; height: 82px; vertical-align: middle; object-fit: contain;" />
    </a>
      
<a href="https://play.google.com/store/apps/details?id=me.deflock.deflockapp" style="display: inline-block;">
<img src="assets/GetItOnGooglePlay_Badge_Web_color_English.png" alt="Download on the Google Play Store" style="width: 246px; height: 82px; vertical-align: middle; object-fit: contain;" />
    </a>
    
---

## What This App Does

- **Map surveillance infrastructure** including cameras, ALPRs, gunshot detectors, and more with precise location, direction, and manufacturer details
- **Upload to OpenStreetMap** with OAuth2 integration (live or sandbox modes)
- **Work completely offline** with downloadable map areas and device data, plus upload queue
- **Multiple map types** including satellite imagery from USGS, Esri, Mapbox, and topographic maps from OpenTopoMap, plus custom map tile provider support
- **Editing Ability** to update existing device locations and properties
- **Built-in device profiles** for Flock Safety, Motorola, Genetec, Leonardo, and other major manufacturers, plus custom profiles for more specific tag sets

---

## Key Features

### Map & Navigation
- **Multi-source tiles**: Switch between OpenStreetMap, USGS imagery, Esri imagery, Mapbox, OpenTopoMap, and any custom providers
- **Offline-first design**: Download a region for complete offline operation
- **Smooth UX**: Intuitive controls, follow-me mode with GPS rotation, compass indicator with north-lock, and gesture-friendly interactions
- **Device visualization**: Color-coded markers showing real devices (blue), pending uploads (purple), pending edits (grey), devices being edited (orange), and pending deletions (red)

### Device Management
- **Comprehensive profiles**: Built-in profiles for major manufacturers (Flock Safety, Motorola/Vigilant, Genetec, Leonardo/ELSAG, Neology) plus custom profile creation
- **Full CRUD operations**: Create, edit, and delete surveillance devices
- **Multi-direction support**: Devices can have multiple viewing directions (e.g. "90;180") with individual field-of-view cones
- **Direction visualization**: Interactive field-of-view cones showing camera viewing angles with opacity-based selection
- **Bulk operations**: Tag multiple devices efficiently with profile-based workflow

### Surveillance Intelligence
- **Suspected locations**: Display potential surveillance sites from utility permit data with dynamic field display (select locations, more added regularly)
- **Proximity alerts**: Get notified when approaching mapped surveillance devices, with configurable distance and background notifications
- **Location search**: Find addresses and points of interest to aid in mapping missions

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

1. **Install** the app on iOS or Android - a welcome popup will guide you through key information
2. **Enable location** permissions  
3. **Log into OpenStreetMap**: Choose upload mode and get OAuth2 credentials
4. **Add your first device**: Tap the "New Node" button, position the pin, set direction(s), select a profile, and tap submit
5. **Edit or delete devices**: Tap any device marker to view details, then use Edit or Delete buttons

**New to OpenStreetMap?** Visit [deflock.me](https://deflock.me) for complete setup instructions and community guidelines.

**App Updates**: The app will automatically show you what's new when you update. You can always view release notes in Settings > About.

---

## For Developers

**See [DEVELOPER.md](DEVELOPER.md)** for comprehensive technical documentation including:
- Architecture overview and design decisions
- Development setup and build instructions  
- Release process and GitHub Actions automation
- Code organization and contribution guidelines
- Debugging tips and troubleshooting

**Quick setup:**
```shell
flutter pub get
cp lib/keys.dart.example lib/keys.dart
# Add OAuth2 client IDs, then: flutter run
```

**Releases**: The app uses GitHub's release system for automated building and store uploads. Simply create a GitHub release and use the "pre-release" checkbox to control whether builds go to app stores - checked for beta releases, unchecked for production releases.

---

## Roadmap

### Needed Bugfixes
- Are offline areas preferred for fast loading even when online? Check working.
- Fix network indicator - only done when fetch queue is empty!

### Current Development
- Suspected locations expansion to more regions
- Import/Export map providers
- Swap in alprwatch.org/directions avoidance routing API
- Clean cache when nodes have disappeared / been deleted by others / queue item was deleted
- Improve offline area node refresh live display
- Add Rekor profile

### Future Features & Wishlist
- Update offline area nodes while browsing?
- Offline navigation (pending vector map tiles)

### Maybes
- Yellow ring for devices missing specific tag details
- "Cache accumulating" offline area
- "Offline areas" as tile provider
- Grab the full latest database for each profile just like for suspected locations (instead of overpass)
- Optional custom icons for profiles to aid identification
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
