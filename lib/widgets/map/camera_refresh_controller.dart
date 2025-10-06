import 'package:flutter/material.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/node_profile.dart';
import '../../app_state.dart' show UploadMode;
import '../camera_provider_with_cache.dart';
import '../../dev_config.dart';

/// Manages camera data refreshing, profile change detection, and camera cache operations.
/// Handles debounced camera fetching and profile-based cache invalidation.
class CameraRefreshController {
  late final CameraProviderWithCache _cameraProvider;
  List<NodeProfile>? _lastEnabledProfiles;
  VoidCallback? _onCamerasUpdated;

  /// Initialize the camera refresh controller
  void initialize({required VoidCallback onCamerasUpdated}) {
    _cameraProvider = CameraProviderWithCache.instance;
    _onCamerasUpdated = onCamerasUpdated;
    _cameraProvider.addListener(_onCamerasUpdated!);
  }

  /// Dispose of resources and listeners
  void dispose() {
    if (_onCamerasUpdated != null) {
      _cameraProvider.removeListener(_onCamerasUpdated!);
    }
  }

  /// Check if camera profiles changed and handle cache clearing if needed.
  /// Returns true if profiles changed (triggering a refresh).
  bool checkAndHandleProfileChanges({
    required List<NodeProfile> currentEnabledProfiles,
    required VoidCallback onProfilesChanged,
  }) {
    if (_lastEnabledProfiles == null || 
        !_profileListsEqual(_lastEnabledProfiles!, currentEnabledProfiles)) {
      _lastEnabledProfiles = List.from(currentEnabledProfiles);
      
      // Handle profile change with cache clearing and refresh
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Clear camera cache to ensure fresh data for new profile combination
        _cameraProvider.clearCache();
        // Force display refresh first (for immediate UI update)
        _cameraProvider.refreshDisplay();
        // Notify that profiles changed (triggers camera refresh)
        onProfilesChanged();
      });
      
      return true;
    }
    return false;
  }

  /// Refresh cameras from provider for the current map view
  void refreshCamerasFromProvider({
    required AnimatedMapController controller,
    required List<NodeProfile> enabledProfiles,
    required UploadMode uploadMode,
    required BuildContext context,
  }) {
    LatLngBounds? bounds;
    try {
      bounds = controller.mapController.camera.visibleBounds;
    } catch (_) {
      return;
    }
    
    final zoom = controller.mapController.camera.zoom;
    if (zoom < kNodeMinZoomLevel) {
      // Show a snackbar-style bubble warning
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nodes not drawn below zoom level $kNodeMinZoomLevel'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    
    _cameraProvider.fetchAndUpdate(
      bounds: bounds,
      profiles: enabledProfiles,
      uploadMode: uploadMode,
    );
  }

  /// Get the camera provider instance for external access
  CameraProviderWithCache get cameraProvider => _cameraProvider;

  /// Helper to check if two profile lists are equal by comparing IDs
  bool _profileListsEqual(List<NodeProfile> list1, List<NodeProfile> list2) {
    if (list1.length != list2.length) return false;
    // Compare by profile IDs since profiles are value objects
    final ids1 = list1.map((p) => p.id).toSet();
    final ids2 = list2.map((p) => p.id).toSet();
    return ids1.length == ids2.length && ids1.containsAll(ids2);
  }
}