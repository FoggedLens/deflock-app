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
└── UploadQueueState (pending operations)
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

## Core Components

### 1. MapDataProvider

**Purpose**: Unified interface for fetching map tiles and surveillance nodes

**Design decisions:**
- **Pluggable sources**: Local (cached) vs Remote (live API)
- **Offline-first**: Always try local first, graceful degradation
- **Mode-aware**: Different behavior for production vs sandbox
- **Failure handling**: Never crash the UI, always provide fallbacks

**Key methods:**
- `getNodes()`: Smart fetching with local/remote merging
- `getTile()`: Tile fetching with caching
- `_fetchRemoteNodes()`: Handles Overpass → OSM API fallback

**Why unified interface:**
The app needs to seamlessly switch between multiple data sources (local cache, Overpass API, OSM API, offline areas) based on network status, upload mode, and zoom level. A single interface prevents the UI from needing to know about these complexities.

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

### 5. Multi-API Data Sources

**Production mode:** Overpass API → OSM API fallback
**Sandbox mode:** OSM API only (Overpass doesn't have sandbox data)

**Zoom level restrictions:**
- **Production (Overpass)**: Zoom ≥ 10 (established limit)
- **Sandbox (OSM API)**: Zoom ≥ 13 (stricter due to bbox limits)

**Why different zoom limits:**
The OSM API returns ALL data types (nodes, ways, relations) in a bounding box and has stricter size limits. Overpass is more efficient for large areas. The zoom restrictions prevent API errors and excessive data transfer.

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