import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;

import '../services/map_data_provider.dart';
import '../services/node_cache.dart';
import '../services/network_status.dart';
import '../models/node_profile.dart';
import '../models/osm_node.dart';
import '../app_state.dart';

/// Provides surveillance nodes for a map view, using an in-memory cache and optionally
/// merging in new results from Overpass via MapDataProvider when not offline.
class NodeProviderWithCache extends ChangeNotifier {
  static final NodeProviderWithCache instance = NodeProviderWithCache._internal();
  factory NodeProviderWithCache() => instance;
  NodeProviderWithCache._internal();

  Timer? _debounceTimer;

  /// Call this to get (quickly) all cached overlays for the given view.
  /// Filters by currently enabled profiles only. Limiting is handled by MapView.
  List<OsmNode> getCachedNodesForBounds(LatLngBounds bounds) {
    final allNodes = NodeCache.instance.queryByBounds(bounds);
    final enabledProfiles = AppState.instance.enabledProfiles;
    
    // If no profiles are enabled, show no nodes
    if (enabledProfiles.isEmpty) return [];
    
    // Filter nodes to only show those matching enabled profiles
    return allNodes.where((node) {
      return _matchesAnyProfile(node, enabledProfiles);
    }).toList();
  }

  /// Call this when the map view changes (bounds/profiles), triggers async fetch
  /// and notifies listeners/UI when new data is available.
  void fetchAndUpdate({
    required LatLngBounds bounds,
    required List<NodeProfile> profiles,
    UploadMode uploadMode = UploadMode.production,
  }) {
    // Fast: serve cached immediately
    notifyListeners();
    // Debounce rapid panning/zooming
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        // Use MapSource.auto to handle both offline and online modes appropriately
        final fresh = await MapDataProvider().getNodes(
          bounds: bounds,
          profiles: profiles,
          uploadMode: uploadMode,
          source: MapSource.auto,
        );
        if (fresh.isNotEmpty) {
          NodeCache.instance.addOrUpdate(fresh);
        // Clear waiting status when node data arrives
          NetworkStatus.instance.clearWaiting();
          notifyListeners();
        }
      } catch (e) {
        debugPrint('[NodeProviderWithCache] Node fetch failed: $e');
        // Cache already holds whatever is available for the view
      }
    });
  }

  /// Clear the cache and repopulate with pending nodes from upload queue
  void clearCache() {
    NodeCache.instance.clear();
    // Repopulate with pending nodes from upload queue if available
    _repopulatePendingNodesAfterClear();
    notifyListeners();
  }

  /// Repopulate pending nodes after cache clear
  void _repopulatePendingNodesAfterClear() {
    // We need access to the upload queue state, but we don't have direct access here
    // Instead, we'll trigger a callback that the app state can handle
    // For now, let's use a more direct approach through a global service access
    // This could be refactored to use proper dependency injection later
    Future.microtask(() {
      // This will be called from app state when cache clears happen
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

  /// Check if a node matches a specific profile (all profile tags must match)
  bool _nodeMatchesProfile(OsmNode node, NodeProfile profile) {
    for (final entry in profile.tags.entries) {
      if (node.tags[entry.key] != entry.value) return false;
    }
    return true;
  }
}