import 'dart:async';
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
  
  // Track ongoing user-initiated requests for status reporting
  final Set<String> _userInitiatedRequests = <String>{};
  
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
        NetworkStatus.instance.clear();
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
        
        // Show brief success for user-initiated offline loads with data
        if (isUserInitiated && offlineNodes.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            NetworkStatus.instance.setSuccess();
          });
        } else if (isUserInitiated && offlineNodes.isEmpty) {
          // Show no data briefly for offline areas with no surveillance devices
          WidgetsBinding.instance.addPostFrameCallback((_) {
            NetworkStatus.instance.setNoData();
          });
        }
        
        return offlineNodes;
      }
    }

    // Handle sandbox mode (always fetch from OSM API, but integrate with cache system for UI)
    if (uploadMode == UploadMode.sandbox) {
      debugPrint('[NodeDataManager] Sandbox mode: fetching from OSM API');
      
      // Track user-initiated requests for status reporting
      final requestKey = '${bounds.hashCode}_${profiles.map((p) => p.id).join('_')}_$uploadMode';
      
      if (isUserInitiated && _userInitiatedRequests.contains(requestKey)) {
        debugPrint('[NodeDataManager] Sandbox request already in progress for this area');
        return _cache.getNodesFor(bounds);
      }
      
      // Start status tracking for user-initiated requests
      if (isUserInitiated) {
        _userInitiatedRequests.add(requestKey);
        NetworkStatus.instance.setLoading();
        debugPrint('[NodeDataManager] Starting user-initiated sandbox request');
      } else {
        debugPrint('[NodeDataManager] Starting background sandbox request (no status reporting)');
      }
      
      try {
        final nodes = await fetchOsmApiNodes(
          bounds: bounds,
          profiles: profiles,
          uploadMode: uploadMode,
          maxResults: 0,
        );
        
        // Add nodes to cache for UI integration (even though we don't rely on cache for subsequent fetches)
        if (nodes.isNotEmpty) {
          _cache.addOrUpdateNodes(nodes);
          _cache.markAreaAsFetched(bounds, nodes);
        } else {
          // Mark area as fetched even with no nodes so UI knows we've checked this area
          _cache.markAreaAsFetched(bounds, []);
        }
        
        // Update UI
        notifyListeners();
        
        // Set success after the next frame renders, but only for user-initiated requests
        if (isUserInitiated) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            NetworkStatus.instance.setSuccess();
          });
          debugPrint('[NodeDataManager] User-initiated sandbox request completed successfully: ${nodes.length} nodes');
        }
        
        return nodes;
        
      } catch (e) {
        debugPrint('[NodeDataManager] Sandbox fetch failed: $e');
        
        // Only report errors for user-initiated requests
        if (isUserInitiated) {
          if (e is RateLimitError) {
            NetworkStatus.instance.setRateLimited();
          } else if (e.toString().contains('timeout')) {
            NetworkStatus.instance.setTimeout();
          } else {
            NetworkStatus.instance.setError();
          }
          debugPrint('[NodeDataManager] User-initiated sandbox request failed: $e');
        }
        
        // Return whatever we have in cache for this area (likely empty for sandbox)
        return _cache.getNodesFor(bounds);
      } finally {
        if (isUserInitiated) {
          _userInitiatedRequests.remove(requestKey);
        }
      }
    }

    // Production mode: check cache first
    if (_cache.hasDataFor(bounds)) {
      debugPrint('[NodeDataManager] Using cached data for bounds');
      return _cache.getNodesFor(bounds);
    }

    // Not cached - need to fetch
    final requestKey = '${bounds.hashCode}_${profiles.map((p) => p.id).join('_')}_$uploadMode';
    
    // Only allow one user-initiated request per area at a time
    if (isUserInitiated && _userInitiatedRequests.contains(requestKey)) {
      debugPrint('[NodeDataManager] User request already in progress for this area');
      return _cache.getNodesFor(bounds);
    }
    
    // Start status tracking for user-initiated requests only
    if (isUserInitiated) {
      _userInitiatedRequests.add(requestKey);
      NetworkStatus.instance.setLoading();
      debugPrint('[NodeDataManager] Starting user-initiated request');
    } else {
      debugPrint('[NodeDataManager] Starting background request (no status reporting)');
    }

    try {
      final nodes = await fetchWithSplitting(bounds, profiles, isUserInitiated: isUserInitiated);
      
      // Update cache and notify listeners
      notifyListeners();
      
      // Set success after the next frame renders, but only for user-initiated requests
      if (isUserInitiated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          NetworkStatus.instance.setSuccess();
        });
        debugPrint('[NodeDataManager] User-initiated request completed successfully');
      }
      
      return nodes;
      
    } catch (e) {
      debugPrint('[NodeDataManager] Fetch failed: $e');
      
      // Only report errors for user-initiated requests
      if (isUserInitiated) {
        if (e is RateLimitError) {
          NetworkStatus.instance.setRateLimited();
        } else if (e.toString().contains('timeout')) {
          NetworkStatus.instance.setTimeout();
        } else {
          NetworkStatus.instance.setError();
        }
        debugPrint('[NodeDataManager] User-initiated request failed: $e');
      }
      
      // Return whatever we have in cache for this area
      return _cache.getNodesFor(bounds);
    } finally {
      if (isUserInitiated) {
        _userInitiatedRequests.remove(requestKey);
      }
    }
  }

  /// Fetch nodes with automatic area splitting if needed
  Future<List<OsmNode>> fetchWithSplitting(
    LatLngBounds bounds, 
    List<NodeProfile> profiles, {
    int splitDepth = 0,
    bool isUserInitiated = false,
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
      
      // Only report splitting status for user-initiated requests
      if (isUserInitiated && splitDepth == 0) {
        NetworkStatus.instance.setSplitting();
      }
      
      return _fetchSplitAreas(bounds, profiles, splitDepth + 1, isUserInitiated: isUserInitiated);
      
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
    int splitDepth, {
    bool isUserInitiated = false,
  }) async {
    final quadrants = _splitBounds(bounds);
    final allNodes = <OsmNode>[];
    
    for (final quadrant in quadrants) {
      try {
        final nodes = await fetchWithSplitting(
          quadrant, 
          profiles, 
          splitDepth: splitDepth, 
          isUserInitiated: isUserInitiated,
        );
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
    _cache.clear();
    
    // Re-fetch as user-initiated request
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