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
- `getTile()`: Tile fetching with enhanced retry strategy (6 attempts, 1-8s delays)
- `_fetchRemoteNodes()`: Handles Overpass → OSM API fallback

**Smart caching flow:**
1. Check if current view within cached area AND data <60s old
2. If not: trigger pre-fetch of 3x larger area, show loading state
3. Return cache immediately for responsive UI
4. When pre-fetch completes: update cache, refresh UI, report success

**Why this approach:**
Reduces API load by 3-4x while ensuring data freshness. User sees instant responses from cache while background fetching keeps data current. Eliminates complex dual-path logic in favor of simple spatial/temporal triggers.

### 2. Node Operations (Create/Edit/Delete)

**Upload Operations Enum:**
```dart
enum UploadOperation { create, modify, delete }
```

**Why explicit enum vs boolean flags:**
- **Brutalist**: Three explicit states instead of nullable booleans
- **Extensible**: Easy to add new operations (like bulk operations)
- **Clear intent**: `operation == UploadOperation.delete` is unambiguous

**Session Pattern:**
- `AddNodeSession`: For creating new nodes
- `EditNodeSession`: For modifying existing nodes
- No "DeleteSession": Deletions are immediate (simpler)

**Why no delete session:**
Deletions don't need position dragging or tag editing - they just need confirmation and queuing. A session would add complexity without benefit.

### 3. Upload Queue System

**Design principles:**
- **Operation-agnostic**: Same queue handles create/modify/delete
- **Offline-capable**: Queue persists between app sessions
- **Visual feedback**: Each operation type has distinct UI state
- **Error recovery**: Retry mechanism with exponential backoff

**Queue workflow:**
1. User action (add/edit/delete) → `PendingUpload` created
2. Immediate visual feedback (cache updated with temp markers)
3. Background uploader processes queue when online
4. Success → cache updated with real data, temp markers removed
5. Failure → error state, retry available

**Why immediate visual feedback:**
Users expect instant response to their actions. By immediately updating the cache with temporary markers (e.g., `_pending_deletion`), the UI stays responsive while the actual API calls happen in background.

### 4. Cache & Visual States

**Node visual states:**
- **Blue ring**: Real nodes from OSM
- **Purple ring**: Pending uploads (new nodes)
- **Grey ring**: Original nodes with pending edits
- **Orange ring**: Node currently being edited
- **Red ring**: Nodes pending deletion

**Cache tags for state tracking:**
```dart
'_pending_upload'    // New node waiting to upload
'_pending_edit'      // Original node has pending edits
'_pending_deletion'  // Node queued for deletion
'_original_node_id'  // For drawing connection lines
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

### 6. Offline vs Online Mode Behavior

**Mode combinations:**
```
Production + Online  → Local cache + Overpass API
Production + Offline → Local cache only
Sandbox + Online     → OSM API only (no cache mixing)
Sandbox + Offline    → No nodes (cache is production data)
```

**Why sandbox + offline = no nodes:**
Local cache contains production data. Showing production nodes in sandbox mode would be confusing and could lead to users trying to edit production nodes with sandbox credentials.

### 7. Proximity Alerts & Background Monitoring

**Design approach:**
- **Simple cooldown system**: In-memory tracking to prevent notification spam
- **Dual alert types**: Push notifications (background) and visual banners (foreground)
- **Configurable distance**: 25-200 meter alert radius
- **Battery awareness**: Users explicitly opt into background location monitoring

**Implementation notes:**
- Uses Flutter Local Notifications for cross-platform background alerts
- Simple RecentAlert tracking prevents duplicate notifications
- Visual callback system for in-app alerts when app is active

### 8. Compass Indicator & North Lock

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

### 9. Suspected Locations

**Data pipeline:**
- **CSV ingestion**: Downloads utility permit data from alprwatch.org
- **GeoJSON processing**: Handles Point, Polygon, and MultiPolygon geometries
- **Proximity filtering**: Hides suspected locations near confirmed devices
- **Regional availability**: Currently select locations, expanding regularly

**Why utility permits:**
Utility companies often must file permits when installing surveillance infrastructure. This creates a paper trail that can indicate potential surveillance sites before devices are confirmed through direct observation.

### 10. Upload Mode Simplification

**Release vs Debug builds:**
- **Release builds**: Production OSM only (simplified UX)
- **Debug builds**: Full sandbox/simulate options available
Most users should contribute to production; testing modes add complexity

**Implementation:**
```dart
// Upload mode selection disabled in release builds
bool get showUploadModeSelector => kDebugMode;
```

### 11. Navigation & Routing (Implemented, Awaiting Integration)

**Current state:**
- **Search functionality**: Fully implemented and active
- **Basic routing**: Complete but disabled pending API integration
- **Avoidance routing**: Awaiting alprwatch.org/directions API
- **Offline routing**: Requires vector map tiles

**Architecture:**
- NavigationState manages routing computation and turn-by-turn instructions
- RoutingService handles API communication and route calculation
- SearchService provides location lookup and geocoding

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