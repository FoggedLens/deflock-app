# Upload System Refactor - v1.5.3

## Overview
Refactored the upload queue processing and OSM submission logic to properly handle the three distinct phases of OSM node operations, fixing the core issue where step 2 failures (node operations) weren't handled correctly.

## Problem Analysis
The previous implementation incorrectly treated OSM interaction as a 2-step process:
1. ~~Open changeset + submit node~~ (conflated)
2. Close changeset

But OSM actually requires 3 distinct steps:
1. **Create changeset** 
2. **Perform node operation** (create/modify/delete)
3. **Close changeset**

### Issues Fixed:
- **Step 2 failure handling**: Node operation failures now properly close orphaned changesets and retry appropriately
- **State confusion**: Users now see exactly which of the 3 stages is happening or failed  
- **Error tracking**: Each stage has appropriate retry logic and error messages
- **UI clarity**: Displays "Creating changeset...", "Uploading...", "Closing changeset..." with progress info

## Changes Made

### 1. Uploader Service (`lib/services/uploader.dart`)
- **Simplified UploadResult**: Replaced complex boolean flags with simple `success/failure` pattern
- **Three explicit methods**:
  - `createChangeset(PendingUpload)` → Returns changeset ID
  - `performNodeOperation(PendingUpload, changesetId)` → Returns node ID  
  - `closeChangeset(changesetId)` → Returns success/failure
- **Legacy compatibility**: `upload()` method still exists for simulate mode
- **Better error context**: Each method provides specific error messages for its stage

### 2. Upload Queue State (`lib/state/upload_queue_state.dart`)
- **Three processing methods**: 
  - `_processCreateChangeset()` - Stage 1
  - `_processNodeOperation()` - Stage 2  
  - `_processChangesetClose()` - Stage 3
- **Proper state transitions**: Clear progression through `pending` → `creatingChangeset` → `uploading` → `closingChangeset` → `complete`
- **Stage-specific retry logic**:
  - Stage 1 failure: Simple retry (no cleanup)
  - Stage 2 failure: Close orphaned changeset, retry from stage 1
  - Stage 3 failure: Exponential backoff up to 59 minutes
- **Simulate mode support**: All three stages work in simulate mode

### 3. Upload Queue UI (`lib/screens/upload_queue_screen.dart`)
- **Enhanced status display**: Shows retry attempts and time remaining (only when changeset close has failed)
- **Better error visibility**: Tap error icon to see detailed failure messages
- **Stage progression**: Clear visual feedback for each of the 3 stages
- **Cleaner progress display**: Time countdown only shows when there have been changeset close issues

### 4. Cache Cleanup (`lib/state/upload_queue_state.dart`, `lib/services/node_cache.dart`)
- **Fixed orphaned pending nodes**: Removing or clearing queue items now properly cleans up temporary cache markers
- **Operation-specific cleanup**:
  - **Creates**: Remove temporary nodes with `_pending_upload` markers
  - **Edits**: Remove temp nodes + `_pending_edit` markers from originals
  - **Deletes**: Remove `_pending_deletion` markers from originals
  - **Extracts**: Remove temp extracted nodes (leave originals unchanged)
- **Added NodeCache methods**: `removePendingDeletionMarker()` for deletion cancellation cleanup

### 5. Documentation Updates
- **DEVELOPER.md**: Added detailed explanation of three-stage architecture
- **Changelog**: Updated v1.5.3 release notes to highlight the fix
- **Code comments**: Improved throughout for clarity

## Architecture Benefits

### Brutalist Code Principles Applied:
1. **Explicit over implicit**: Three methods instead of one complex method
2. **Simple error handling**: Success/failure instead of multiple boolean flags
3. **Clear responsibilities**: Each method does exactly one thing
4. **Minimal state complexity**: Straightforward state machine progression

### User Experience Improvements:
- **Transparent progress**: Users see exactly what stage is happening
- **Better error messages**: Specific context about which stage failed
- **Proper retry behavior**: Stage 2 failures no longer leave orphaned changesets
- **Time awareness**: Countdown shows when OSM will auto-close changesets

### Maintainability Gains:
- **Easier debugging**: Each stage can be tested independently
- **Clear failure points**: No confusion about which step failed
- **Simpler testing**: Individual stages are unit-testable
- **Future extensibility**: Easy to add new upload operations or modify stages

## Refined Retry Logic (Post-Testing Updates)

After initial testing feedback, the retry logic was refined to properly handle the 59-minute changeset window:

### Three-Phase Retry Strategy:
- **Phase 1 (Create Changeset)**: Up to 3 attempts with 20s delays → Error state (user retry required)
- **Phase 2 (Submit Node)**: Unlimited attempts within 59-minute window → Error if time expires
- **Phase 3 (Close Changeset)**: Unlimited attempts within 59-minute window → Auto-complete if time expires (trust OSM auto-close)

### Key Behavioral Changes:
- **59-minute timer starts** when changeset creation succeeds (not when node operation completes)
- **Node submission failures** retry indefinitely within the 59-minute window
- **Changeset close failures** retry indefinitely but never error out (always eventually complete)
- **UI countdown** only shows when there have been failures in phases 2 or 3
- **Proper error messages**: "Failed to create changeset after 3 attempts" vs "Could not submit node within 59 minutes"

## Testing Recommendations

When testing this refactor:

1. **Normal uploads**: Verify all three stages show proper progression
2. **Network interruption**: 
   - Test failure at each stage individually
   - Verify orphaned changesets are properly closed
   - Check retry logic works appropriately
3. **Error handling**:
   - Tap error icons to see detailed messages
   - Verify different error types show stage-specific context
4. **Simulate mode**: Confirm all three stages work in simulate mode
5. **Queue management**: Verify queue continues processing when individual items fail
6. **Changeset closing**: Test that changeset close retries work with exponential backoff

## Rollback Plan
If issues are discovered, the legacy `upload()` method can be restored by:
1. Reverting `_processCreateChangeset()` to call `up.upload(item)` directly
2. Removing `_processNodeOperation()` and `_processChangesetClose()` calls
3. This would restore the old 2-stage behavior while keeping the UI improvements

---

The core fix addresses the main issue you identified: **step 2 failures (node operations) are now properly tracked and handled with appropriate cleanup and retry logic**.