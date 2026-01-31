import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/node_profile.dart';
import '../models/osm_node.dart';
import '../app_state.dart';
import 'overpass_service.dart';
import 'node_spatial_cache.dart';
import 'network_status.dart';
import 'map_data_submodules/nodes_from_osm_api.dart';
import 'map_data_submodules/nodes_from_local.dart';
import 'offline_area_service.dart';
import 'offline_areas/offline_area_models.dart';

/// Coordinates node data fetching between cache, Overpass, and OSM API.
/// Simple interface: give me nodes for this view with proper caching and error handling.
class NodeDataManager extends ChangeNotifier {
  static final NodeDataManager _instance = NodeDataManager._();
  factory NodeDataManager() => _instance;
  NodeDataManager._();

  final OverpassService _overpassService = OverpassService();
  final NodeSpatialCache _cache = NodeSpatialCache();
  
  // Track ongoing requests and which one is "primary" for status reporting
  final Set<String> _activeRequests = <String>{};
  String? _primaryRequestKey; // The latest request that should drive NetworkStatus
  
  /// Get nodes for the given bounds and profiles.
  /// Returns cached data immediately if available, otherwise fetches from appropriate source.
  Future<List<OsmNode>> getNodesFor({
    required LatLngBounds bounds,
    required List<NodeProfile> profiles,
    UploadMode uploadMode = UploadMode.production,
    bool isUserInitiated = false,
  }) async {
    if (profiles.isEmpty) return [];

    // Handle offline mode - no loading states needed, data is instant
    if (AppState.instance.offlineMode) {
      // Clear any existing loading states since offline data is instant
      if (isUserInitiated) {
        NetworkStatus.instance.clearWaiting();
      }
      
      if (uploadMode == UploadMode.sandbox) {
        // Offline + Sandbox = no nodes (local cache is production data)
        debugPrint('[NodeDataManager] Offline + Sandbox mode: returning no nodes');
        return [];
      } else {
        // Offline + Production = use local offline areas (instant)
        final offlineNodes = await fetchLocalNodes(bounds: bounds, profiles: profiles);
        
        // Add offline nodes to cache so they integrate with the rest of the system
        if (offlineNodes.isNotEmpty) {
          _cache.addOrUpdateNodes(offlineNodes);
          // Mark this area as having coverage for submit button logic
          _cache.markAreaAsFetched(bounds, offlineNodes);
          notifyListeners();
        }
        
        // Show brief success for user-initiated offline loads
        if (isUserInitiated && offlineNodes.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            NetworkStatus.instance.setSuccess();
          });
        }
        
        return offlineNodes;
      }
    }

    // Handle sandbox mode (always fetch from OSM API, no caching)
    if (uploadMode == UploadMode.sandbox) {
      debugPrint('[NodeDataManager] Sandbox mode: fetching from OSM API');
      return fetchOsmApiNodes(
        bounds: bounds,
        profiles: profiles,
        uploadMode: uploadMode,
        maxResults: 0,
      );
    }

    // Production mode: check cache first
    if (_cache.hasDataFor(bounds)) {
      debugPrint('[NodeDataManager] Using cached data for bounds');
      return _cache.getNodesFor(bounds);
    }

    // Not cached - need to fetch
    // Create a unique key for this request to prevent duplicates
    final requestKey = '${bounds.hashCode}_${profiles.map((p) => p.id).join('_')}_$uploadMode';
    final bool isDuplicate = _activeRequests.contains(requestKey);
    final bool isPrimaryRequest = isUserInitiated;
    
    if (isDuplicate && !isPrimaryRequest) {
      debugPrint('[NodeDataManager] Background request already in progress for this area, returning cached data');
      return _cache.getNodesFor(bounds);
    }
    
    // Set this as primary request if user-initiated (most recent)
    if (isPrimaryRequest) {
      _primaryRequestKey = requestKey;
      NetworkStatus.instance.setWaiting();
      debugPrint('[NodeDataManager] Starting PRIMARY request (${_activeRequests.length + 1} total active)');
    } else {
      debugPrint('[NodeDataManager] Starting background request (${_activeRequests.length + 1} total active)');
    }

    _activeRequests.add(requestKey);
    try {
      final nodes = await fetchWithSplitting(bounds, profiles);
      
      // Don't set success immediately - wait for UI to render the nodes
      notifyListeners();
      
      // Set success after the next frame renders, but only for primary requests
      if (isPrimaryRequest && _primaryRequestKey == requestKey) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          NetworkStatus.instance.setSuccess();
        });
        debugPrint('[NodeDataManager] PRIMARY request completed successfully');
      } else {
        debugPrint('[NodeDataManager] Background request completed successfully');
      }
      
      return nodes;
      
    } catch (e) {
      debugPrint('[NodeDataManager] Fetch failed: $e');
      
      // Only report errors for primary requests to avoid status confusion
      if (isPrimaryRequest && _primaryRequestKey == requestKey) {
        if (e is RateLimitError) {
          NetworkStatus.instance.reportOverpassIssue();
        } else {
          NetworkStatus.instance.setNetworkError();
        }
        debugPrint('[NodeDataManager] PRIMARY request failed: $e');
      } else {
        debugPrint('[NodeDataManager] Background request failed: $e');
      }
      
      // Return whatever we have in cache for this area
      return _cache.getNodesFor(bounds);
    } finally {
      _activeRequests.remove(requestKey);
      // Clear primary key if this was the primary request
      if (_primaryRequestKey == requestKey) {
        _primaryRequestKey = null;
      }
    }
  }

  /// Fetch nodes with automatic area splitting if needed
  Future<List<OsmNode>> fetchWithSplitting(
    LatLngBounds bounds, 
    List<NodeProfile> profiles, {
    int splitDepth = 0,
  }) async {
    const maxSplitDepth = 3; // 4^3 = 64 max sub-areas
    
    try {
      // Expand bounds slightly to reduce edge effects
      final expandedBounds = _expandBounds(bounds, 1.2);
      
      final nodes = await _overpassService.fetchNodes(
        bounds: expandedBounds,
        profiles: profiles,
      );
      
      // Success - cache the data for the expanded area
      _cache.markAreaAsFetched(expandedBounds, nodes);
      return nodes;
      
    } on NodeLimitError {
      // Hit node limit or timeout - split area if not too deep
      if (splitDepth >= maxSplitDepth) {
        debugPrint('[NodeDataManager] Max split depth reached, giving up');
        return [];
      }
      
      debugPrint('[NodeDataManager] Splitting area (depth: $splitDepth)');
      NetworkStatus.instance.reportSlowProgress();
      
      return _fetchSplitAreas(bounds, profiles, splitDepth + 1);
      
    } on RateLimitError {
      // Rate limited - wait and return empty
      debugPrint('[NodeDataManager] Rate limited, backing off');
      await Future.delayed(const Duration(seconds: 30));
      return [];
    }
  }

  /// Fetch data by splitting area into quadrants
  Future<List<OsmNode>> _fetchSplitAreas(
    LatLngBounds bounds, 
    List<NodeProfile> profiles,
    int splitDepth,
  ) async {
    final quadrants = _splitBounds(bounds);
    final allNodes = <OsmNode>[];
    
    for (final quadrant in quadrants) {
      try {
        final nodes = await fetchWithSplitting(quadrant, profiles, splitDepth: splitDepth);
        allNodes.addAll(nodes);
      } catch (e) {
        debugPrint('[NodeDataManager] Quadrant fetch failed: $e');
        // Continue with other quadrants
      }
    }
    
    debugPrint('[NodeDataManager] Split fetch complete: ${allNodes.length} total nodes');
    return allNodes;
  }

  /// Split bounds into 4 quadrants
  List<LatLngBounds> _splitBounds(LatLngBounds bounds) {
    final centerLat = (bounds.north + bounds.south) / 2;
    final centerLng = (bounds.east + bounds.west) / 2;
    
    return [
      // Southwest
      LatLngBounds(LatLng(bounds.south, bounds.west), LatLng(centerLat, centerLng)),
      // Southeast  
      LatLngBounds(LatLng(bounds.south, centerLng), LatLng(centerLat, bounds.east)),
      // Northwest
      LatLngBounds(LatLng(centerLat, bounds.west), LatLng(bounds.north, centerLng)),
      // Northeast
      LatLngBounds(LatLng(centerLat, centerLng), LatLng(bounds.north, bounds.east)),
    ];
  }

  /// Expand bounds by given factor around center point
  LatLngBounds _expandBounds(LatLngBounds bounds, double factor) {
    final centerLat = (bounds.north + bounds.south) / 2;
    final centerLng = (bounds.east + bounds.west) / 2;
    
    final latSpan = (bounds.north - bounds.south) * factor / 2;
    final lngSpan = (bounds.east - bounds.west) * factor / 2;
    
    return LatLngBounds(
      LatLng(centerLat - latSpan, centerLng - lngSpan),
      LatLng(centerLat + latSpan, centerLng + lngSpan),
    );
  }

  /// Add or update nodes in cache (for upload queue integration)
  void addOrUpdateNodes(List<OsmNode> nodes) {
    _cache.addOrUpdateNodes(nodes);
    notifyListeners();
  }

  /// Remove node from cache (for deletions)
  void removeNodeById(int nodeId) {
    _cache.removeNodeById(nodeId);
    notifyListeners();
  }

  /// Clear cache (when profiles change significantly)
  void clearCache() {
    _cache.clear();
    notifyListeners();
  }

  /// Force refresh for current view (manual retry)
  Future<void> refreshArea({
    required LatLngBounds bounds,
    required List<NodeProfile> profiles,
    UploadMode uploadMode = UploadMode.production,
  }) async {
    // Clear any cached data for this area
    _cache.clear(); // Simple: clear everything for now
    
    // Re-fetch
    await getNodesFor(
      bounds: bounds,
      profiles: profiles,
      uploadMode: uploadMode,
      isUserInitiated: true,
    );
  }

  /// NodeCache compatibility methods
  OsmNode? getNodeById(int nodeId) => _cache.getNodeById(nodeId);
  void removePendingEditMarker(int nodeId) => _cache.removePendingEditMarker(nodeId);
  void removePendingDeletionMarker(int nodeId) => _cache.removePendingDeletionMarker(nodeId);
  void removeTempNodeById(int tempNodeId) => _cache.removeTempNodeById(tempNodeId);
  List<OsmNode> findNodesWithinDistance(LatLng coord, double distanceMeters, {int? excludeNodeId}) =>
      _cache.findNodesWithinDistance(coord, distanceMeters, excludeNodeId: excludeNodeId);

  /// Check if we have good cache coverage for the given area
  bool hasGoodCoverageFor(LatLngBounds bounds) {
    return _cache.hasDataFor(bounds);
  }

  /// Load all offline nodes into cache (call at app startup)
  Future<void> preloadOfflineNodes() async {
    try {
      final offlineAreaService = OfflineAreaService();
      
      for (final area in offlineAreaService.offlineAreas) {
        if (area.status != OfflineAreaStatus.complete) continue;
        
        // Load nodes from this offline area
        final nodes = await fetchLocalNodes(
          bounds: area.bounds,
          profiles: [], // Empty profiles = load all nodes
        );
        
        if (nodes.isNotEmpty) {
          _cache.addOrUpdateNodes(nodes);
          // Mark the offline area as having coverage so submit buttons work
          _cache.markAreaAsFetched(area.bounds, nodes);
          debugPrint('[NodeDataManager] Preloaded ${nodes.length} offline nodes from area ${area.name}');
        }
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('[NodeDataManager] Error preloading offline nodes: $e');
    }
  }

  /// Get cache statistics
  String get cacheStats => _cache.stats.toString();
}