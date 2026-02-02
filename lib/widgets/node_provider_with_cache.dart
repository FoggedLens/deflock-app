import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;

import '../services/node_data_manager.dart';
import '../services/node_spatial_cache.dart';
import '../models/node_profile.dart';
import '../models/osm_node.dart';
import '../app_state.dart';

/// Provides surveillance nodes for a map view, using an in-memory cache and optionally
/// merging in new results from Overpass via MapDataProvider when not offline.
class NodeProviderWithCache extends ChangeNotifier {
  static final NodeProviderWithCache instance = NodeProviderWithCache._internal();
  factory NodeProviderWithCache() => instance;
  NodeProviderWithCache._internal();

  final NodeDataManager _nodeDataManager = NodeDataManager();
  Timer? _debounceTimer;

  /// Get cached nodes for the given bounds, filtered by enabled profiles
  List<OsmNode> getCachedNodesForBounds(LatLngBounds bounds) {
    // Use the same cache instance as NodeDataManager
    final allNodes = NodeSpatialCache().getNodesFor(bounds);
    final enabledProfiles = AppState.instance.enabledProfiles;
    
    // If no profiles are enabled, show no nodes
    if (enabledProfiles.isEmpty) return [];
    
    // Filter nodes to only show those matching enabled profiles
    return allNodes.where((node) {
      return _matchesAnyProfile(node, enabledProfiles);
    }).toList();
  }

  /// Fetch and update nodes for the given view, with debouncing for rapid map movement
  void fetchAndUpdate({
    required LatLngBounds bounds,
    required List<NodeProfile> profiles,
    UploadMode uploadMode = UploadMode.production,
  }) {
    // Serve cached immediately
    notifyListeners();
    
    // Debounce rapid panning/zooming
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        await _nodeDataManager.getNodesFor(
          bounds: bounds,
          profiles: profiles,
          uploadMode: uploadMode,
          isUserInitiated: true,
        );
        
        // Notify UI of new data
        notifyListeners();
        
      } catch (e) {
        debugPrint('[NodeProviderWithCache] Node fetch failed: $e');
        // Cache already holds whatever is available for the view
      }
    });
  }

  /// Clear the cache and repopulate with pending nodes from upload queue
  void clearCache() {
    _nodeDataManager.clearCache();
    // Repopulate with pending nodes from upload queue if available
    _repopulatePendingNodesAfterClear();
    notifyListeners();
  }

  /// Repopulate pending nodes after cache clear
  void _repopulatePendingNodesAfterClear() {
    Future.microtask(() {
      _onCacheCleared?.call();
    });
  }

  VoidCallback? _onCacheCleared;

  /// Set callback for when cache is cleared (used by app state to repopulate pending nodes)
  void setOnCacheClearedCallback(VoidCallback? callback) {
    _onCacheCleared = callback;
  }

  /// Force refresh the display (useful when filters change but cache doesn't)
  void refreshDisplay() {
    notifyListeners();
  }

  /// Check if a node matches any of the provided profiles
  bool _matchesAnyProfile(OsmNode node, List<NodeProfile> profiles) {
    for (final profile in profiles) {
      if (_nodeMatchesProfile(node, profile)) return true;
    }
    return false;
  }

  /// Check if a node matches a specific profile (all non-empty profile tags must match)
  bool _nodeMatchesProfile(OsmNode node, NodeProfile profile) {
    for (final entry in profile.tags.entries) {
      // Skip empty values - they are used for refinement UI, not matching
      if (entry.value.trim().isEmpty) continue;
      
      if (node.tags[entry.key] != entry.value) return false;
    }
    return true;
  }
}