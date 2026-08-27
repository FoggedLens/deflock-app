import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'services/offline_area_service.dart';
import 'services/overpass_service.dart';
import 'services/profile_service.dart';
import 'services/suspected_location_cache.dart';
import 'widgets/nuclear_reset_dialog.dart';
import 'dev_config.dart';


/// One-time migrations that run when users upgrade to specific versions.
/// Each migration function is named after the version where it should run.
class OneTimeMigrations {
  /// Enable network status indicator for all existing users (v1.3.1)
  static Future<void> migrate_1_3_1(AppState appState) async {
    await appState.setNetworkStatusIndicatorEnabled(true);
    debugPrint('[Migration] 1.3.1 completed: enabled network status indicator');
  }

  /// Migrate upload queue to new two-stage changeset system (v1.5.3)
  static Future<void> migrate_1_5_3(AppState appState) async {
    // Migration is handled automatically in PendingUpload.fromJson via _migrateFromLegacyFields
    // This triggers a queue reload to apply migrations
    await appState.reloadUploadQueue();
    debugPrint('[Migration] 1.5.3 completed: migrated upload queue to two-stage system');
  }

  /// Clear FOV values from built-in profiles only (v1.6.3)
  static Future<void> migrate_1_6_3(AppState appState) async {
    // Load all custom profiles from storage (includes any customized built-in profiles)
    final profiles = await ProfileService().load();
    
    // Find profiles with built-in IDs and clear their FOV values
    final updatedProfiles = profiles.map((profile) {
      if (profile.id.startsWith('builtin-') && profile.fov != null) {
        debugPrint('[Migration] Clearing FOV from profile: ${profile.id}');
        return profile.copyWith(fov: null);
      }
      return profile;
    }).toList();
    
    // Save updated profiles back to storage
    await ProfileService().save(updatedProfiles);
    
    debugPrint('[Migration] 1.6.3 completed: cleared FOV values from built-in profiles');
  }

  /// Migrate suspected locations from SharedPreferences to SQLite (v1.8.0)
  static Future<void> migrate_1_8_0(AppState appState) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Legacy SharedPreferences keys
      const legacyProcessedDataKey = 'suspected_locations_processed_data';
      const legacyLastFetchKey = 'suspected_locations_last_fetch';
      
      // Check if we have legacy data
      final legacyData = prefs.getString(legacyProcessedDataKey);
      final legacyLastFetch = prefs.getInt(legacyLastFetchKey);
      
      if (legacyData != null && legacyLastFetch != null) {
        debugPrint('[Migration] 1.8.0: Found legacy suspected location data, migrating to database...');
        
        // Parse legacy processed data format
        final List<dynamic> legacyProcessedList = jsonDecode(legacyData);
        final List<Map<String, dynamic>> rawDataList = [];
        
        for (final entry in legacyProcessedList) {
          if (entry is Map<String, dynamic> && entry['rawData'] != null) {
            rawDataList.add(Map<String, dynamic>.from(entry['rawData']));
          }
        }
        
        if (rawDataList.isNotEmpty) {
          final fetchTime = DateTime.fromMillisecondsSinceEpoch(legacyLastFetch);
          
          // Get the cache instance and migrate data
          final cache = SuspectedLocationCache();
          await cache.loadFromStorage(); // Initialize database
          await cache.processAndSave(rawDataList, fetchTime);
          
          debugPrint('[Migration] 1.8.0: Migrated ${rawDataList.length} entries from legacy storage');
        }
        
        // Clean up legacy data after successful migration
        await prefs.remove(legacyProcessedDataKey);
        await prefs.remove(legacyLastFetchKey);
        
        debugPrint('[Migration] 1.8.0: Legacy data cleanup completed');
      }
      
      // Ensure suspected locations are reinitialized with new system
      await appState.reinitSuspectedLocations();
      
      debugPrint('[Migration] 1.8.0 completed: migrated suspected locations to SQLite database');
    } catch (e) {
      debugPrint('[Migration] 1.8.0 ERROR: Failed to migrate suspected locations: $e');
      // Don't rethrow - migration failure shouldn't break the app
      // The new system will work fine, users just lose their cached data
    }
  }

  /// Clear any active sessions to reset refined tags system (v2.1.0)
  static Future<void> migrate_2_1_0(AppState appState) async {
    try {
      // Clear any existing sessions since they won't have refinedTags field
      // This is simpler and safer than trying to migrate session data
      appState.cancelSession();
      appState.cancelEditSession();
      
      debugPrint('[Migration] 2.1.0 completed: cleared sessions for refined tags system');
    } catch (e) {
      debugPrint('[Migration] 2.1.0 ERROR: Failed to clear sessions: $e');
      // Don't rethrow - this is non-critical
    }
  }

  /// Initialize profile ordering for existing users (v2.7.3)
  static Future<void> migrate_2_7_3(AppState appState) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const orderKey = 'profile_order';
      
      // Check if user already has custom profile ordering
      if (prefs.containsKey(orderKey)) {
        debugPrint('[Migration] 2.7.3: Profile order already exists, skipping');
        return;
      }
      
      // Initialize with current profile order (preserves existing UI order)
      final currentProfiles = appState.profiles;
      final initialOrder = currentProfiles.map((p) => p.id).toList();
      
      if (initialOrder.isNotEmpty) {
        await prefs.setStringList(orderKey, initialOrder);
        debugPrint('[Migration] 2.7.3: Initialized profile order with ${initialOrder.length} profiles');
      }
      
      debugPrint('[Migration] 2.7.3 completed: initialized profile ordering');
    } catch (e) {
      debugPrint('[Migration] 2.7.3 ERROR: Failed to initialize profile ordering: $e');
      // Don't rethrow - this is non-critical, profiles will just use default order
    }
  }

  /// Clear non-360 FOV values from all profiles (v2.10.0)
  static Future<void> migrate_2_10_0(AppState appState) async {
    try {
      // Only perform this migration if non-360 FOVs are disabled
      if (kEnableNon360FOVs) {
        debugPrint('[Migration] 2.10.0: Non-360 FOVs enabled, skipping FOV cleanup');
        return;
      }

      // Load all profiles from storage
      final profiles = await ProfileService().load();
      bool anyProfileChanged = false;
      int profilesCleared = 0;

      // Clear non-360 FOV values from all profiles
      final updatedProfiles = profiles.map((profile) {
        if (profile.fov != null) {
          // Use approximation to handle floating point precision issues
          final fovValue = profile.fov!;
          final is360 = (fovValue - 360.0).abs() < 0.01; // Within 0.01 degrees of 360
          
          if (!is360) {
            debugPrint('[Migration] 2.10.0: Clearing FOV $fovValue from profile: ${profile.name}');
            anyProfileChanged = true;
            profilesCleared++;
            return profile.copyWith(fov: null);
          }
        }
        return profile;
      }).toList();

      // Save updated profiles back to storage if any changes were made
      if (anyProfileChanged) {
        await ProfileService().save(updatedProfiles);
        await appState.reloadProfiles();
        debugPrint('[Migration] 2.10.0: Cleared FOV from $profilesCleared profiles');
      }

      debugPrint('[Migration] 2.10.0 completed: cleared non-360 FOV values from profiles');
    } catch (e, stackTrace) {
      debugPrint('[Migration] 2.10.0 ERROR: Failed to clear non-360 FOV values: $e');
      debugPrint('[Migration] 2.10.0 ERROR: Stack trace: $stackTrace');
      // Don't rethrow - this is non-critical, FOV restrictions will still apply going forward
    }
  }

  /// Enable offline features for existing users who already have offline
  /// area data (v2.10.5). New installs and existing users who never used
  /// offline areas will keep the new "offline features enabled" setting at
  /// its default of false.
  static Future<void> migrate_2_10_5(AppState appState) async {
    try {
      final offlineAreaService = OfflineAreaService();
      await offlineAreaService.ensureInitialized();

      if (offlineAreaService.offlineAreas.isNotEmpty) {
        await appState.setOfflineFeaturesEnabled(true);
        debugPrint('[Migration] 2.10.5: Existing offline area data found - enabled offline features');
      } else {
        debugPrint('[Migration] 2.10.5: No existing offline area data - leaving offline features disabled');
      }

      debugPrint('[Migration] 2.10.5 completed: offline features migration done');
    } catch (e) {
      debugPrint('[Migration] 2.10.5 ERROR: Failed to migrate offline features setting: $e');
      // Don't rethrow - this is non-critical, worst case is the user needs
      // to manually re-enable the toggle to see their existing offline areas.
    }
  }

  /// Fix Flock Raven tags that were using the wrong surveillance scheme (v2.11.1)
  /// Old (incorrect): 'surveillance': 'public', 'brand': 'Flock Safety', 'brand:wikidata': 'Q108485435'
  /// New (correct): 'surveillance': 'outdoor', 'manufacturer': 'Flock Safety', 'manufacturer:wikidata': 'Q108485435'
  static Future<void> migrate_2_11_1(AppState appState) async {
    try {
      // Fix the persisted profile catalog (used when creating new nodes going forward)
      final profiles = await ProfileService().load();
      bool profilesChanged = false;

      final updatedProfiles = profiles.map((profile) {
        final tags = profile.tags;
        if (tags['surveillance'] == 'public' &&
            tags['brand'] == 'Flock Safety' &&
            tags['surveillance:type'] == 'gunshot_detector') {
          debugPrint('[Migration] 2.11.1: Fixing Flock Raven tags on profile: ${profile.id}');
          final newTags = Map<String, String>.from(tags);
          final wikidata = newTags.remove('brand:wikidata');
          newTags.remove('brand');
          newTags['surveillance'] = 'outdoor';
          newTags['manufacturer'] = 'Flock Safety';
          newTags['manufacturer:wikidata'] = wikidata ?? 'Q108485435';
          profilesChanged = true;
          return profile.copyWith(tags: newTags);
        }
        return profile;
      }).toList();

      if (profilesChanged) {
        await ProfileService().save(updatedProfiles);
        await appState.reloadProfiles();
      }

      // Fix any not-yet-uploaded queue entries that snapshotted the old tags
      final queueChanged = await appState.migrateFlockRavenQueueTags();

      debugPrint('[Migration] 2.11.1 completed: fixed Flock Raven tags '
          '(profiles changed=$profilesChanged, queue changed=$queueChanged)');
    } catch (e, stackTrace) {
      debugPrint('[Migration] 2.11.1 ERROR: Failed to fix Flock Raven tags: $e');
      debugPrint('[Migration] 2.11.1 ERROR: Stack trace: $stackTrace');
      // Don't rethrow - non-critical, worst case stale tags persist until manually fixed
    }
  }

  /// Get the migration function for a specific version
  static Future<void> Function(AppState)? getMigrationForVersion(String version) {
    switch (version) {
      case '1.3.1':
        return migrate_1_3_1;
      case '1.5.3':
        return migrate_1_5_3;
      case '1.6.3':
        return migrate_1_6_3;
      case '1.8.0':
        return migrate_1_8_0;
      case '2.1.0':
        return migrate_2_1_0;
      case '2.7.3':
        return migrate_2_7_3;
      case '2.10.0':
        return migrate_2_10_0;
      case '2.10.5':
        return migrate_2_10_5;
      case '2.11.1':
        return migrate_2_11_1;
      default:
        return null;
    }
  }


  /// Run migration for a specific version with nuclear reset on failure
  static Future<void> runMigration(String version, AppState appState, BuildContext? context) async {
    try {
      final migration = getMigrationForVersion(version);
      if (migration != null) {
        await migration(appState);
      } else {
        debugPrint('[Migration] Unknown migration version: $version');
      }
    } catch (error, stackTrace) {
      debugPrint('[Migration] CRITICAL: Migration $version failed: $error');
      debugPrint('[Migration] Stack trace: $stackTrace');
      
      // Nuclear option: clear everything and show non-dismissible error dialog
      if (context != null && context.mounted) {
        NuclearResetDialog.show(context, error, stackTrace);
      } else {
        // If no context available, just log and hope for the best
        debugPrint('[Migration] No context available for error dialog, migration failure unhandled');
      }
    }
  }
}

/// One-time (not version-gated) scan of the logged-in user's own live OSM
/// data for nodes still using the old Flock Raven tag scheme, offering to
/// correct them. Runs at most once ever: skipped permanently once the user
/// has answered the prompt, or once a scan finds nothing to fix. A failed
/// scan (e.g. offline) is *not* marked as done, so it's retried on a later
/// launch once conditions allow.
class FlockRavenLiveDataFix {
  static const _promptedKey = 'flock_raven_live_fix_prompted';

  /// The old (incorrect) Flock Raven tag scheme this scan looks for.
  static const Map<String, String> _staleTags = {
    'man_made': 'surveillance',
    'surveillance': 'public',
    'surveillance:type': 'gunshot_detector',
    'brand': 'Flock Safety',
  };

  static Future<void> checkAndPrompt(AppState appState, BuildContext? context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_promptedKey) == true) return;

      if (!appState.isLoggedIn || appState.username.isEmpty) {
        debugPrint('[FlockRavenLiveFix] Not logged in, will retry on a later launch');
        return;
      }

      if (context == null || !context.mounted) {
        debugPrint('[FlockRavenLiveFix] No context available, will retry on a later launch');
        return;
      }

      debugPrint('[FlockRavenLiveFix] Scanning OSM for stale Flock Raven nodes owned by ${appState.username}');
      final staleNodes = await OverpassService().fetchNodesByUserAndTags(
        username: appState.username,
        tagFilter: _staleTags,
      );

      if (staleNodes.isEmpty) {
        debugPrint('[FlockRavenLiveFix] No stale nodes found, marking as done');
        await prefs.setBool(_promptedKey, true);
        return;
      }

      if (!context.mounted) return; // Re-check after the async scan

      final count = staleNodes.length;
      final shouldFix = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Update Flock Raven tags?'),
          content: Text(
            'Found $count Flock Raven ${count == 1 ? 'node' : 'nodes'} on your OpenStreetMap '
            'account using outdated tags. Update ${count == 1 ? 'it' : 'them'} to the correct tags now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Yes'),
            ),
          ],
        ),
      );

      if (shouldFix == true) {
        final queued = appState.addFlockRavenCorrections(staleNodes);
        debugPrint('[FlockRavenLiveFix] Queued ${queued.length} corrective uploads');
      } else {
        debugPrint('[FlockRavenLiveFix] User declined the live data fix');
      }

      // Never ask again, regardless of the answer.
      await prefs.setBool(_promptedKey, true);
    } catch (e, stackTrace) {
      debugPrint('[FlockRavenLiveFix] ERROR: Scan/prompt failed: $e');
      debugPrint('[FlockRavenLiveFix] Stack trace: $stackTrace');
      // Don't mark as prompted - retry on a later launch
    }
  }

  /// Dev-only: clear the "already prompted" flag so the scan/prompt fires
  /// again on the next app launch, without needing a full app/data reset.
  static Future<void> resetPromptedFlagForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_promptedKey);
    debugPrint('[FlockRavenLiveFix] Reset prompted flag for testing');
  }
}