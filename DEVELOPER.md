# Developer Documentation

This document provides detailed technical information about the DeFlock app architecture, key design decisions, and development guidelines.

---

## Philosophy: Brutalist Code

Our development approach prioritizes **simplicity over cleverness**:

- **Explicit over implicit**: Clear, readable code that states its intent
- **Few edge cases by design**: Avoid complex branching and special cases
- **Maintainable over efficient**: Choose the approach that's easier to understand and modify
- **Delete before adding**: Remove complexity when possible rather than adding features

**Hierarchy of preferred code:**
1. **Code we don't write** (through thoughtful design and removing edge cases)
2. **Code we can remove** (by seeing problems from a new angle)
3. **Code that sadly must exist** (simple, explicit, maintainable)

---

## Architecture Overview

### State Management

The app uses **Provider pattern** with modular state classes:

```
AppState (main coordinator)
├── AuthState (OAuth2 login/logout)
├── OperatorProfileState (operator tag sets)
├── ProfileState (node profiles & toggles)
├── SessionState (add/edit sessions)
├── SettingsState (preferences & tile providers)
├── UploadQueueState (pending operations)
├── SuspectedLocationState (permit data & display)
├── NavigationState (routing & search)
└── SearchState (location search results)
```

**Why this approach:**
- **Separation of concerns**: Each state handles one domain
- **Testability**: Individual state classes can be unit tested
- **Brutalist**: No complex state orchestration, just simple delegation

### Data Flow Architecture

```
UI Layer (Widgets)
    ↕️
AppState (Coordinator) 
    ↕️
State Modules (AuthState, ProfileState, etc.)
    ↕️
Services (MapDataProvider, NodeCache, Uploader)
    ↕️
External APIs (OSM, Overpass, Tile providers)
```

**Key principles:**
- **Unidirectional data flow**: UI → AppState → Services → APIs
- **No direct service access from UI**: Everything goes through AppState
- **Clean boundaries**: Each layer has a clear responsibility

---

## Changelog & First Launch System

The app includes a comprehensive system for welcoming new users and notifying existing users of updates.

### Components
- **ChangelogService**: Manages version tracking and changelog loading
- **WelcomeDialog**: First launch popup with privacy information and quick links
- **SubmissionGuideDialog**: One-time popup before first node submission with best practices
- **ChangelogDialog**: Update notification popup for version changes  
- **ReleaseNotesScreen**: Settings page for viewing all changelog history

### Content Management
Changelog content is stored in `assets/changelog.json`:
```json
{
  "1.2.4": {
    "content": "• New feature description\n• Bug fixes\n• Other improvements"
  },
  "1.2.3": {
    "content": ""  // Empty string = skip popup for this version
  }
}
```

### Developer Workflow
1. **For each release**: Add entry to `changelog.json` with version from `pubspec.yaml`
2. **Content required**: Every version must have an entry (can be empty string to skip)
3. **Localization**: Welcome dialog supports i18n, changelog content is English-only
4. **Testing**: Clear app data to test first launch, change version to test updates

### User Experience Flow
- **First Launch**: Welcome popup with "don't show again" option
- **First Submission**: Submission guide popup with best practices and resource links
- **Version Updates**: Changelog popup (only if content exists, no "don't show again")  
- **Settings Access**: Complete changelog history available in Settings > About > Release Notes

### Privacy Integration
The welcome popup explains that the app:
- Runs entirely locally on device
- Uses OpenStreetMap API for data storage only
- DeFlock collects no user data
- DeFlock is not responsible for OSM account management

---

## Core Components

### 1. MapDataProvider & Smart Area Caching

**Purpose**: Unified interface for fetching map tiles and surveillance nodes with intelligent area caching

**Design decisions:**
- **Single fetch strategy**: Uses PrefetchAreaService for smart 3x area caching instead of dual immediate/background fetching
- **Spatial + temporal refresh**: Fetches larger areas (3x visible bounds) and refreshes stale data (>60s old)
- **Offline-first**: Always try local cache first, graceful degradation
- **Mode-aware**: Different behavior for production vs sandbox
- **Failure handling**: Never crash the UI, always provide fallbacks

**Key methods:**
- `getNodes()`: Returns cache immediately, triggers pre-fetch if needed (spatial or temporal)
- `getTile()`: Tile fetching with unlimited retry strategy (retries until success)
- `_fetchRemoteNodes()`: Handles Overpass → OSM API fallback

**Smart caching flow:**
1. Check if current view within cached area AND data <60s old
2. If not: trigger pre-fetch of 3x larger area, show loading state
3. Return cache immediately for responsive UI
4. When pre-fetch completes: update cache, refresh UI, report success

**Why this approach:**
Reduces API load by 3-4x while ensuring data freshness. User sees instant responses from cache while background fetching keeps data current. Eliminates complex dual-path logic in favor of simple spatial/temporal triggers.

### 2. Node Operations (Create/Edit/Delete/Extract)

**Upload Operations Enum:**
```dart
enum UploadOperation { create, modify, delete, extract }
```

**Why explicit enum vs boolean flags:**
- **Brutalist**: Four explicit states instead of nullable booleans
- **Extensible**: Easy to add new operations (like bulk operations)
- **Clear intent**: `operation == UploadOperation.delete` is unambiguous

**Operations explained:**
- **create**: Add new node to OSM
- **modify**: Update existing node's tags/position/direction
- **delete**: Remove existing node from OSM
- **extract**: Create new node with tags copied from constrained node, leaving original unchanged

**Session Pattern:**
- `AddNodeSession`: For creating new nodes with single or multiple directions
- `EditNodeSession`: For modifying existing nodes, preserving all existing directions
- No "DeleteSession": Deletions are immediate (simpler)

**Multi-Direction Support:**
Sessions use a simple model for handling multiple directions:
```dart
class AddNodeSession {
  List<double> directions;          // [90, 180, 270] - all directions
  int currentDirectionIndex;        // Which direction is being edited
  
  // Slider always shows the current direction
  double get directionDegrees => directions[currentDirectionIndex];
  set directionDegrees(value) => directions[currentDirectionIndex] = value;
}
```

**Direction Interaction:**
- **Add**: New directions start at 0° and are automatically selected for editing
- **Remove**: Current direction removed from list (minimum 1 direction)
- **Cycle**: Switch between existing directions in the list
- **Submit**: All directions combined as semicolon-separated string (e.g., "90;180;270")

**Why no delete session:**
Deletions don't need position dragging or tag editing - they just need confirmation and queuing. A session would add complexity without benefit.

### 3. Upload Queue System & Three-Stage Upload Process

**Design principles:**
- **Three explicit stages**: Create changeset → Upload node → Close changeset
- **Operation-agnostic**: Same queue handles create/modify/delete/extract
- **Offline-capable**: Queue persists between app sessions  
- **Visual feedback**: Each operation type and stage has distinct UI state
- **Stage-specific error recovery**: Appropriate retry logic for each of the 3 stages

**Three-stage upload workflow:**
1. **Stage 1 - Create Changeset**: Generate changeset XML and create on OSM
   - Retries: Up to 3 attempts with 20s delays
   - Failures: Reset to pending for full retry
2. **Stage 2 - Node Operation**: Create/modify/delete the surveillance node
   - Retries: Up to 3 attempts with 20s delays  
   - Failures: Close orphaned changeset, then retry from stage 1
3. **Stage 3 - Close Changeset**: Close the changeset to finalize
   - Retries: Exponential backoff up to 59 minutes
   - Failures: OSM auto-closes after 60 minutes, so we eventually give up

**Queue processing workflow:**
1. User action (add/edit/delete) → `PendingUpload` created with `UploadState.pending`
2. Immediate visual feedback (cache updated with temp markers)
3. Background uploader processes queue when online:
   - **Pending** → Create changeset → **CreatingChangeset** → **Uploading**
   - **Uploading** → Upload node → **ClosingChangeset** 
   - **ClosingChangeset** → Close changeset → **Complete**
4. Success → cache updated with real data, temp markers removed
5. Failures → appropriate retry logic based on which stage failed

**Why three explicit stages:**
The previous implementation conflated changeset creation + node operation as one step, making error handling unclear. The new approach:
- **Tracks which stage failed**: Users see exactly what went wrong
- **Handles step 2 failures correctly**: Node operation failures now properly close orphaned changesets  
- **Provides clear UI feedback**: "Creating changeset...", "Uploading...", "Closing changeset..."
- **Enables appropriate retry logic**: Different stages have different retry needs

**Stage-specific error handling:**
- **Stage 1 failure**: Simple retry (no cleanup needed)
- **Stage 2 failure**: Close orphaned changeset, then retry from stage 1
- **Stage 3 failure**: Keep retrying with exponential backoff (most important for OSM data integrity)

**Why immediate visual feedback:**
Users expect instant response to their actions. By immediately updating the cache with temporary markers (e.g., `_pending_deletion`), the UI stays responsive while the actual API calls happen in background.

**Queue persistence & cache synchronization (v1.5.4+):**
- **Startup repopulation**: Queue initialization now repopulates cache with pending nodes, ensuring visual continuity after app restarts
- **Specific node cleanup**: Each upload stores a `tempNodeId` for precise removal, preventing accidental cleanup of other pending nodes at the same location
- **Proximity awareness**: Proximity warnings now consider pending nodes to prevent duplicate submissions at the same location
- **Processing status UI**: Upload queue screen shows clear indicators when processing is paused due to offline mode or user settings

### 4. Cache & Visual States

**Node visual states:**
- **Blue ring**: Real nodes from OSM
- **Purple ring**: Pending uploads (new nodes)
- **Grey ring**: Original nodes with pending edits
- **Orange ring**: Node currently being edited
- **Red ring**: Nodes pending deletion

**Direction cone visual states:**
- **Full opacity**: Active session direction (currently being edited)
- **Reduced opacity (40%)**: Inactive session directions
- **Standard opacity**: Existing node directions (when not in edit mode)

**Cache tags for state tracking:**
```dart
'_pending_upload'    // New node waiting to upload
'_pending_edit'      // Original node has pending edits
'_pending_deletion'  // Node queued for deletion
'_original_node_id'  // For drawing connection lines
```

**Multi-direction parsing:**
The app supports nodes with multiple directions specified as semicolon-separated values:
```dart
// OSM tag: direction="90;180;270"
List<double> get directionDeg {
  final raw = tags['direction'] ?? tags['camera:direction'];
  // Splits on semicolons, parses each direction, normalizes to 0-359°
  return [90.0, 180.0, 270.0]; // Results in multiple FOV cones
}
```

**Why underscore prefix:**
These are internal app tags, not OSM tags. The underscore prefix makes this explicit and prevents accidental upload to OSM.

### 5. Enhanced Overpass Integration & Error Handling

**Production mode:** Overpass API → OSM API fallback
**Sandbox mode:** OSM API only (Overpass doesn't have sandbox data)

**Zoom level restrictions:**
- **Production (Overpass)**: Zoom ≥ 10 (established limit)
- **Sandbox (OSM API)**: Zoom ≥ 13 (stricter due to bbox limits)

**Smart error handling & splitting:**
- **50k node limit**: Automatically splits query into 4 quadrants, recursively up to 3 levels deep
- **Timeout errors**: Also triggers splitting (dense areas with many profiles)  
- **Rate limiting**: Extended backoff (30s), no splitting (would make it worse)
- **Surgical detection**: Only splits on actual limit errors, not network issues

**Query optimization:**
- **Pre-fetch limit**: 4x user's display limit (e.g., 1000 nodes for 250 display limit)
- **User-initiated detection**: Only reports loading status for user-facing operations  
- **Background operations**: Pre-fetch runs silently, doesn't trigger loading states

**Why this approach:**
Dense urban areas (SF, NYC) with many profiles enabled can easily exceed both 50k node limits and 25s timeouts. Splitting reduces query complexity while surgical error detection avoids unnecessary API load from network issues.

### 6. Uploader Service Architecture (Refactored v1.5.3)

**Three-method approach:**
The `Uploader` class now provides three distinct methods matching the OSM API workflow:

```dart
// Step 1: Create changeset
Future<UploadResult> createChangeset(PendingUpload p) async

// Step 2: Perform node operation (create/modify/delete/extract) 
Future<UploadResult> performNodeOperation(PendingUpload p, String changesetId) async

// Step 3: Close changeset
Future<UploadResult> closeChangeset(String changesetId) async
```

**Simplified UploadResult:**
Replaced complex boolean flags with simple success/failure:
```dart
UploadResult.success({changesetId, nodeId})  // Operation succeeded
UploadResult.failure({errorMessage, ...})   // Operation failed with details
```

**Legacy compatibility:**
The `upload()` method still exists for simulate mode and backwards compatibility, but now internally calls the three-step methods in sequence.

**Why this architecture:**
- **Brutalist simplicity**: Each method does exactly one thing
- **Clear failure points**: No confusion about which step failed  
- **Easier testing**: Each stage can be unit tested independently
- **Better error messages**: Specific failure context for each stage

### 7. Offline vs Online Mode Behavior

**Mode combinations:**
```
Production + Online  → Local cache + Overpass API
Production + Offline → Local cache only
Sandbox + Online     → OSM API only (no cache mixing)
Sandbox + Offline    → No nodes (cache is production data)
```

**Why sandbox + offline = no nodes:**
Local cache contains production data. Showing production nodes in sandbox mode would be confusing and could lead to users trying to edit production nodes with sandbox credentials.

### 8. Proximity Alerts & Background Monitoring

**Design approach:**
- **Simple cooldown system**: In-memory tracking to prevent notification spam
- **Dual alert types**: Push notifications (background) and visual banners (foreground)
- **Configurable distance**: 25-200 meter alert radius
- **Battery awareness**: Users explicitly opt into background location monitoring

**Implementation notes:**
- Uses Flutter Local Notifications for cross-platform background alerts
- Simple RecentAlert tracking prevents duplicate notifications
- Visual callback system for in-app alerts when app is active

### 9. Compass Indicator & North Lock

**Purpose**: Visual compass showing map orientation with optional north-lock functionality

**Design decisions:**
- **Separate from follow mode**: North lock is independent of GPS following behavior  
- **Smart rotation detection**: Distinguishes intentional rotation (>5°) from zoom gestures
- **Visual feedback**: Clear skeumorphic compass design with red north indicator
- **Mode awareness**: Disabled during follow+rotate mode (incompatible)

**Key behaviors:**
- **North indicator**: Red arrow always points toward true north regardless of map rotation
- **Tap to toggle**: Enable/disable north lock with visual animation to north
- **Auto-disable**: North lock turns off when switching to follow+rotate mode
- **Gesture intelligence**: Only disables on significant rotation changes, ignores zoom artifacts

**Visual states:**
- **Normal**: White background, grey border, red north arrow
- **North locked**: White background, blue border, bright red north arrow
- **Disabled**: Grey background, muted colors (during follow+rotate mode)

**Why separate from follow mode:**
Users often want to follow their location while keeping the map oriented north. Previous "north up" follow mode was confusing because it didn't actually keep north up. This separation provides clear, predictable behavior.

### 10. Network Status Indicator (Simplified in v1.5.2+)

**Purpose**: Show loading and error states for surveillance data fetching only

**Simplified approach (v1.5.2+):**
- **Surveillance data focus**: Only tracks node/camera data loading, not tile loading
- **Visual feedback**: Tiles show their own loading progress naturally
- **Reduced complexity**: Eliminated tile completion tracking and multiple issue types

**Status types:**
- **Loading**: Shows when fetching surveillance data from APIs
- **Success**: Brief confirmation when data loads successfully  
- **Timeout**: Network request timeouts
- **Limit reached**: When node display limit is hit
- **API issues**: Overpass/OSM API problems only

**What was removed:**
- Tile server issue tracking (tiles handle their own progress)
- "Both" network issue type (only surveillance data matters)
- Complex semaphore-based completion detection
- Tile-related status messages and localizations

**Why the change:**
The previous approach tracked both tile loading and surveillance data, creating redundancy since tiles already show loading progress visually on the map. Users don't need to be notified about tile loading issues when they can see tiles loading/failing directly. Focusing only on surveillance data makes the indicator more purposeful and less noisy.

### 11. Suspected Locations

**Data pipeline:**
- **CSV ingestion**: Downloads utility permit data from alprwatch.org
- **Dynamic field parsing**: Stores all CSV columns (except `location` and `ticket_no`) for flexible display
- **GeoJSON processing**: Handles Point, Polygon, and MultiPolygon geometries
- **Proximity filtering**: Hides suspected locations near confirmed devices
- **Regional availability**: Currently select locations, expanding regularly

**Display approach:**
- **Required fields**: `ticket_no` (for heading) and `location` (for map positioning)
- **Dynamic display**: All other CSV fields shown automatically, no hardcoded field list
- **Server control**: Field names and content controlled server-side via CSV headers
- **Brutalist rendering**: Fields displayed as-is from CSV, empty fields hidden

**Why utility permits:**
Utility companies often must file permits when installing surveillance infrastructure. This creates a paper trail that can indicate potential surveillance sites before devices are confirmed through direct observation.

### 12. Upload Mode Simplification

**Release vs Debug builds:**
- **Release builds**: Production OSM only (simplified UX)
- **Debug builds**: Full sandbox/simulate options available
Most users should contribute to production; testing modes add complexity

**Implementation:**
```dart
// Upload mode selection disabled in release builds
bool get showUploadModeSelector => kDebugMode;
```

### 13. Tile Provider System & Clean Architecture (v1.5.2+)

**Architecture (post-v1.5.2):**
- **Custom TileProvider**: Clean Flutter Map integration using `DeflockTileProvider` 
- **Direct MapDataProvider integration**: Tiles go through existing offline/online routing
- **No HTTP interception**: Eliminated fake URLs and complex HTTP clients
- **Simplified caching**: Single cache layer (FlutterMap's internal cache)

**Key components:**
- `DeflockTileProvider`: Custom Flutter Map TileProvider implementation
- `DeflockTileImageProvider`: Handles tile fetching through MapDataProvider
- Automatic offline/online routing: Uses `MapSource.auto` for each tile

**Tile provider configuration:**
- **Flexible URL templates**: Support multiple coordinate systems and load-balancing patterns
- **Built-in providers**: Curated set of high-quality, reliable tile sources  
- **Custom providers**: Users can add any tile service with full validation
- **API key management**: Secure storage with per-provider API keys

**Supported URL placeholders:**
```
{x}, {y}, {z}          - Standard TMS tile coordinates
{quadkey}              - Bing Maps quadkey format (alternative to x/y/z)
{0_3}                  - Subdomain 0-3 for load balancing  
{1_4}                  - Subdomain 1-4 for providers using 1-based indexing
{api_key}              - API key insertion point (optional)
```

**Built-in providers:**
- **OpenStreetMap**: Standard street map tiles, no API key required
- **Bing Maps**: High-quality satellite imagery using quadkey system, no API key required  
- **Mapbox**: Satellite and street tiles, requires API key
- **OpenTopoMap**: Topographic maps, no API key required

**Why the architectural change:**
The previous HTTP interception approach (`SimpleTileHttpClient` with fake URLs) fought against Flutter Map's architecture and created unnecessary complexity. The new `TileProvider` approach:
- **Cleaner integration**: Works with Flutter Map's design instead of against it
- **Smart cache routing**: Only checks offline cache when needed, eliminating expensive filesystem searches
- **Better error handling**: Graceful fallbacks for missing tiles  
- **Cross-platform performance**: Optimizations that work well on both iOS and Android

**Tile Loading Performance Fix (v1.5.2):**
The major performance issue was discovered to be double caching with expensive operations:
1. **Problem**: Every tile request checked offline areas via filesystem I/O, even when no offline data existed
2. **Solution**: Smart cache detection - only check offline cache when in offline mode OR when offline areas actually exist for the current provider
3. **Result**: Dramatically improved tile loading from 0.5-5 tiles/sec back to ~70 tiles/sec for normal browsing

**Cross-Platform Optimizations:**
- **Request deduplication**: Prevents multiple simultaneous requests for identical tile coordinates
- **Optimized retry timing**: Faster initial retry (150ms vs 200ms) with shorter backoff for quicker recovery
- **Queue size limits**: Maximum 100 queued requests to prevent memory bloat
- **Smart queue management**: Drops oldest requests when queue fills up
- **Reduced concurrent connections**: 8 threads instead of 10 for better stability across platforms

### 14. Navigation & Routing (Implemented and Active)

**Current state:**
- **Search functionality**: Fully implemented and active
- **Avoidance routing**: Fully implemented and active
- **Distance feedback**: Shows real-time distance when selecting second route point
- **Long distance warnings**: Alerts users when routes may timeout (configurable threshold)
- **Offline routing**: Requires vector map tiles

**Architecture:**
- NavigationState manages routing computation and turn-by-turn instructions
- RoutingService handles API communication and route calculation
- SearchService provides location lookup and geocoding

**Distance warning system (v1.7.0):**
- **Real-time distance display**: Shows distance from first to second point during selection
- **Configurable threshold**: `kNavigationDistanceWarningThreshold` in dev_config (default 30km)
- **User feedback**: Warning message about potential timeouts for long routes
- **Brutalist approach**: Simple distance calculation using existing `Distance()` utility

---

## Key Design Decisions & Rationales

### 1. Why Provider Pattern?

**Alternatives considered:**
- BLoC: Too verbose for our needs
- Riverpod: Added complexity without clear benefit
- setState: Doesn't scale beyond single widgets

**Why Provider won:**
- **Familiar**: Most Flutter developers know Provider
- **Simple**: Minimal boilerplate
- **Flexible**: Easy to compose multiple providers
- **Battle-tested**: Mature, stable library

### 2. Why Separate State Classes?

**Alternative**: Single monolithic AppState

**Why modular state:**
- **Single responsibility**: Each state class has one concern
- **Testability**: Easier to unit test individual features
- **Maintainability**: Changes to auth don't affect profile logic
- **Team development**: Different developers can work on different states

### 3. Why Upload Queue vs Direct API Calls?

**Alternative**: Direct API calls from UI actions

**Why queue approach:**
- **Offline capability**: Actions work without internet
- **User experience**: Instant feedback, no waiting for API calls
- **Error recovery**: Failed uploads can be retried
- **Batch processing**: Could optimize multiple operations
- **Visual feedback**: Users can see pending operations

### 4. Why Overpass + OSM API vs Just One?

**Why not just Overpass:**
- Overpass doesn't have sandbox data
- Overpass can be unreliable/slow
- OSM API is canonical source

**Why not just OSM API:**
- OSM API has strict bbox size limits
- OSM API returns all data types (inefficient)
- Overpass is optimized for surveillance device queries

**Result**: Use the best tool for each situation

### 5. Why Zoom Level Restrictions?

**Alternative**: Always fetch, handle errors gracefully

**Why restrictions:**
- **Prevents API abuse**: Large bbox queries can overload servers
- **User experience**: Fetching 10,000 nodes causes UI lag
- **Battery life**: Excessive network requests drain battery
- **Clear feedback**: Users understand why nodes aren't showing

### 6. Why Separate Compass Indicator from Follow Mode?

**Alternative**: Combined "follow with north up" mode

**Why separate controls:**
- **Clear user mental model**: "Follow me" vs "lock to north" are distinct concepts
- **Flexible combinations**: Users can follow without north lock, or vice versa
- **Avoid mode conflicts**: Follow+rotate is incompatible with north lock
- **Reduced confusion**: Previous "north up" mode didn't actually keep north up

**Design benefits:**
- **Brutalist approach**: Two simple, independent features instead of complex mode combinations
- **Visual feedback**: Compass shows exact map orientation regardless of follow state
- **Smart gesture detection**: Differentiates intentional rotation from zoom artifacts
- **Predictable behavior**: Each control does exactly what it says

---

## Development Guidelines

### 1. Adding New Features

**Before writing code:**
1. Can we solve this by removing existing code?
2. Can we simplify the problem to avoid edge cases?
3. Does this fit the existing patterns?

**When adding new upload operations:**
1. Add to `UploadOperation` enum
2. Update `PendingUpload` serialization
3. Add visual state (color, icon)
4. Update uploader logic
5. Add cache cleanup handling

### 2. Testing Philosophy

**Priority order:**
1. **Integration tests**: Test complete user workflows
2. **Widget tests**: Test UI components with mock data
3. **Unit tests**: Test individual state classes

**Why integration tests first:**
The most important thing is that user workflows work end-to-end. Unit tests can pass while the app is broken from a user perspective.

### 3. Error Handling

**Principles:**
- **Never crash the UI**: Always provide fallbacks
- **Fail gracefully**: Empty list is better than exception
- **User feedback**: Show meaningful error messages
- **Logging**: Use debugPrint for troubleshooting

**Example pattern:**
```dart
try {
  final result = await riskyOperation();
  return result;
} catch (e) {
  debugPrint('Operation failed: $e');
  // Show user-friendly message
  showSnackBar('Unable to load data. Please try again.');
  return <EmptyResult>[];
}
```

### 4. State Updates

**Always notify listeners:**
```dart
void updateSomething() {
  _something = newValue;
  notifyListeners(); // Don't forget this!
}
```

**Batch related updates:**
```dart
void updateMultipleThings() {
  _thing1 = value1;
  _thing2 = value2;
  _thing3 = value3;
  notifyListeners(); // Single notification for all changes
}
```

---

## Release Process & GitHub Actions

The app uses a **clean, release-triggered workflow** that rebuilds from scratch for maximum reliability:

### How It Works

**Trigger: GitHub Release Creation**
- Create a GitHub release → Workflow automatically builds, attaches assets, and optionally uploads to stores
- **Pre-release checkbox** controls store uploads:
  - ✅ **Checked** → Build + attach assets (no store uploads)
  - ✅ **Unchecked** → Build + attach assets + upload to App/Play stores

### Release Types

**Development/Beta Releases**
1. Create GitHub release from any tag/branch
2. ✅ **Check "pre-release"** checkbox
3. Publish → Assets built and attached, no store uploads

**Production Releases**  
1. Create GitHub release from main/stable branch
2. ❌ **Leave "pre-release" unchecked**
3. Publish → Assets built and attached + uploaded to stores

### Store Upload Destinations

**Google Play Store:**
- Uploads to **Internal Testing** track
- Requires manual promotion to Beta/Production
- You maintain full control over public release

**App Store Connect:**
- Uploads to **TestFlight**  
- Requires manual App Store submission
- You maintain full control over public release

### Required Secrets

**For Google Play Store Upload:**
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` - Complete JSON service account key (plain text)

**For iOS App Store Upload:**
- `APP_STORE_CONNECT_API_KEY_ID` - App Store Connect API key ID
- `APP_STORE_CONNECT_ISSUER_ID` - App Store Connect issuer ID  
- `APP_STORE_CONNECT_API_KEY_BASE64` - Base64-encoded .p8 API key file

**For Building:**
- `OSM_PROD_CLIENTID` - OpenStreetMap production OAuth2 client ID
- `OSM_SANDBOX_CLIENTID` - OpenStreetMap sandbox OAuth2 client ID
- Android signing secrets (keystore, passwords, etc.)
- iOS signing certificates and provisioning profiles

### Google Play Store Setup

1. **Google Cloud Console:**
   - Create Service Account with "Project Editor" role
   - Enable Google Play Android Developer API
   - Download JSON key file

2. **Google Play Console:**
   - Add service account email to Users & Permissions
   - Grant "Release Manager" permissions for your app
   - Complete first manual release to activate app listing

3. **GitHub Secrets:**
   - Store entire JSON key as `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` (plain text)

### Workflow Benefits

✅ **Brutalist simplicity** - One trigger, clear behavior  
✅ **No external dependencies** - Only uses trusted `r0adkll/upload-google-play@v1`  
✅ **Explicit control** - GitHub's UI checkbox controls store uploads  
✅ **Always rebuilds** - No stale artifacts or cross-workflow complexity  
✅ **Safe defaults** - Pre-release prevents accidental production uploads  
✅ **No tag coordination** - Works with any commit, tag, or branch

---

## Build & Development Setup

### Prerequisites
- **Flutter SDK**: Latest stable version
- **Xcode**: For iOS builds (macOS only)
- **Android Studio**: For Android builds
- **Git**: For version control

### OAuth2 Setup

**Required registrations:**
1. **Production OSM**: https://www.openstreetmap.org/oauth2/applications
2. **Sandbox OSM**: https://master.apis.dev.openstreetmap.org/oauth2/applications

**Configuration:**
```bash
cp lib/keys.dart.example lib/keys.dart
# Edit keys.dart with your OAuth2 client IDs
```

### iOS Setup
```bash
cd ios && pod install
```

### Running
```bash
flutter pub get
flutter run
```

### Testing
```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage
```

---

## Code Organization

```
lib/
├── models/              # Data classes
│   ├── osm_camera_node.dart
│   ├── pending_upload.dart
│   └── node_profile.dart
├── services/            # Business logic
│   ├── map_data_provider.dart
│   ├── uploader.dart
│   └── node_cache.dart
├── state/               # State management
│   ├── app_state.dart
│   ├── auth_state.dart
│   └── upload_queue_state.dart
├── widgets/             # UI components
│   ├── map_view.dart
│   ├── edit_node_sheet.dart
│   └── map/             # Map-specific widgets
├── screens/             # Full screens
│   ├── home_screen.dart
│   └── settings_screen.dart
└── localizations/       # i18n strings
    ├── en.json
    ├── de.json
    ├── es.json
    └── fr.json
```

**Principles:**
- **Models**: Pure data, no business logic
- **Services**: Stateless business logic
- **State**: Stateful coordination
- **Widgets**: UI only, delegate to AppState
- **Screens**: Compose widgets, handle navigation

---

## Debugging Tips

### Common Issues

**Nodes not appearing:**
- Check zoom level (≥10 production, ≥13 sandbox)
- Check upload mode vs expected data source
- Check network connectivity
- Look for console errors

**Upload failures:**
- Verify OAuth2 credentials
- Check upload mode matches login (production vs sandbox)
- Ensure node has required tags
- Check network connectivity

**Cache issues:**
- Clear app data to reset cache
- Check if offline mode is affecting behavior
- Verify upload mode switches clear cache

### Debug Logging

**Enable verbose logging:**
```dart
debugPrint('[ComponentName] Detailed message: $data');
```

**Key areas to log:**
- Network requests and responses
- Cache operations
- State transitions
- User actions

### Performance

**Monitor:**
- Memory usage during large node fetches
- UI responsiveness during background uploads
- Battery usage during GPS tracking

---

This documentation should be updated as the architecture evolves. When making significant changes, update both the relevant section here and add a brief note explaining the rationale for the change.
