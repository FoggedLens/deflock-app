# Network Status Refactor - v2.6.1

## Overview

Completely rewrote the network status indicator system to use a simple enum-based approach instead of multiple boolean flags and complex timer management.

## Key Changes

### Before (Complex)
- Multiple boolean flags: `_overpassHasIssues`, `_isWaitingForData`, `_isTimedOut`, etc.
- Complex state reconciliation logic in `currentStatus` getter
- Multiple independent timers that could conflict
- Both foreground and background requests reporting status
- Inconsistent state transitions

### After (Brutalist)
- Single enum: `NetworkRequestStatus` with 8 clear states
- Simple `_setStatus()` method handles all transitions and timers
- Only user-initiated requests report status (background requests ignored)
- Clear state ownership and no conflicting updates

## New Status States

```dart
enum NetworkRequestStatus {
  idle,        // No active requests (default, no indicator shown)
  loading,     // Initial request in progress
  splitting,   // Request being split due to limits/timeouts  
  success,     // Data loaded successfully (auto-clears in 2s)
  timeout,     // Request timed out (auto-clears in 5s)
  rateLimited, // API rate limited (auto-clears in 2min)
  noData,      // No offline data available (auto-clears in 3s)
  error,       // Other network errors (auto-clears in 5s)
}
```

## Behavior Changes

### Request Splitting
- When a request needs to be split due to node limits or timeouts:
  - Status transitions: `loading` → `splitting` → `success`
  - Only the top-level (original) request manages status
  - Sub-requests (quadrants) complete silently

### Background vs User-Initiated Requests
- **User-initiated**: Pan/zoom actions, manual refresh - report status
- **Background**: Pre-fetch, cache warming - no status reporting
- Only one user-initiated request per area allowed at a time

### Error Handling
- Rate limits: Clear red "Rate limited by server" with 2min timeout
- Network errors: Clear red "Network error" with 5s timeout  
- Timeouts: Orange "Request timed out" with 5s timeout
- No data: Grey "No offline data" with 3s timeout

## Files Modified

### Core Implementation
- `lib/services/network_status.dart` - Complete rewrite (100+ lines → 60 lines)
- `lib/widgets/network_status_indicator.dart` - Updated to use new enum
- `lib/services/node_data_manager.dart` - Simplified status reporting logic

### Status Reporting Cleanup
- `lib/services/map_data_submodules/nodes_from_osm_api.dart` - Removed independent status reporting

### Localization
- Added new strings to all language files:
  - `networkStatus.rateLimited`
  - `networkStatus.networkError`

### Documentation
- `assets/changelog.json` - Added v2.6.1 entry
- `test/services/network_status_test.dart` - Basic unit tests

## Testing Checklist

### Basic Functionality
- [ ] Initial app load shows no network indicator
- [ ] Pan/zoom to new area shows "Loading surveillance data..."
- [ ] Successful load shows "Surveillance data loaded" briefly (2s)
- [ ] Switch to offline mode, then pan - should show no indicator (instant data)

### Error States  
- [ ] Poor network → should show "Network error" (red, 5s timeout)
- [ ] Dense area that requires splitting → "Surveillance data slow" (orange)
- [ ] Offline area with no surveillance data → "No offline data" (grey, 3s)

### Background vs Foreground
- [ ] Background requests (pre-fetch) should not affect indicator
- [ ] Only user pan/zoom actions should trigger status updates
- [ ] Multiple quick pan actions should not create conflicting status

### Split Requests
- [ ] In very dense areas (SF, NYC), splitting should work correctly
- [ ] Status should transition: loading → splitting → success
- [ ] All quadrants must complete before showing success

### Mode Switches
- [ ] Online → Offline: Any ongoing requests should not interfere
- [ ] Production → Sandbox: Should work with new request logic
- [ ] Manual refresh should reset and restart status properly

## Potential Issues to Watch

1. **Timer disposal**: Ensure timers are properly cancelled when app backgrounds
2. **Rapid status changes**: Quick pan actions shouldn't create flicker
3. **Split request coordination**: Verify all sub-requests complete properly
4. **Offline mode integration**: Status should be silent for instant offline data

## Code Quality Improvements

- **Reduced complexity**: 8 enum states vs 5+ boolean combinations
- **Single responsibility**: Each method does one clear thing
- **Brutalist approach**: Simple, explicit, easy to understand
- **Better debugging**: Clear state transitions with logging
- **Fewer race conditions**: Single timer per status type

This refactor dramatically simplifies the network status system while maintaining all existing functionality and improving reliability.