import 'package:flutter/material.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../models/node_profile.dart';
import '../../app_state.dart' show UploadMode;

import '../node_provider_with_cache.dart';
import '../../dev_config.dart';

/// Manages node data refreshing, profile change detection, and node cache operations.
/// Handles debounced node fetching and profile-based cache invalidation.
class NodeRefreshController {
  late final NodeProviderWithCache _nodeProvider;
  List<NodeProfile>? _lastEnabledProfiles;
  VoidCallback? _onNodesUpdated;

  /// Initialize the node refresh controller
  void initialize({required VoidCallback onNodesUpdated}) {
    _nodeProvider = NodeProviderWithCache.instance;
    _onNodesUpdated = onNodesUpdated;
    _nodeProvider.addListener(_onNodesUpdated!);
  }

  /// Dispose of resources and listeners
  void dispose() {
    if (_onNodesUpdated != null) {
      _nodeProvider.removeListener(_onNodesUpdated!);
    }
  }

  /// Check if node profiles changed and handle cache clearing if needed.
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
        // Clear node cache to ensure fresh data for new profile combination
        _nodeProvider.clearCache();
        // Force display refresh first (for immediate UI update)
        _nodeProvider.refreshDisplay();
        // Notify that profiles changed (triggers node refresh)
        onProfilesChanged();
      });
      
      return true;
    }
    return false;
  }

  /// Refresh nodes from provider for the current map view
  void refreshNodesFromProvider({
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
    // Use the correct minimum zoom level based on upload mode
    final minZoom = uploadMode == UploadMode.sandbox ? kOsmApiMinZoomLevel : kNodeMinZoomLevel;
    
    if (zoom < minZoom) {
      // Show a snackbar-style bubble warning with mode-specific message
      if (context.mounted) {
        final message = uploadMode == UploadMode.sandbox 
          ? 'Nodes not drawn below zoom level $minZoom in sandbox mode (OSM API limits)'
          : 'Nodes not drawn below zoom level $minZoom';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    
    _nodeProvider.fetchAndUpdate(
      bounds: bounds,
      profiles: enabledProfiles,
      uploadMode: uploadMode,
    );
  }

  /// Get the node provider instance for external access
  NodeProviderWithCache get nodeProvider => _nodeProvider;

  /// Helper to check if two profile lists are equal by comparing IDs
  bool _profileListsEqual(List<NodeProfile> list1, List<NodeProfile> list2) {
    if (list1.length != list2.length) return false;
    // Compare by profile IDs since profiles are value objects
    final ids1 = list1.map((p) => p.id).toSet();
    final ids2 = list2.map((p) => p.id).toSet();
    return ids1.length == ids2.length && ids1.containsAll(ids2);
  }
}