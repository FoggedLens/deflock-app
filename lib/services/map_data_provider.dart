import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/foundation.dart';

import '../models/node_profile.dart';
import '../models/osm_node.dart';
import '../app_state.dart';
import 'map_data_submodules/tiles_from_remote.dart';
import 'map_data_submodules/tiles_from_local.dart';
import 'node_data_manager.dart';
import 'node_spatial_cache.dart';

enum MapSource { local, remote, auto } // For future use

class OfflineModeException implements Exception {
  final String message;
  OfflineModeException(this.message);
  @override
  String toString() => 'OfflineModeException: $message';
}

class MapDataProvider {
  static final MapDataProvider _instance = MapDataProvider._();
  factory MapDataProvider() => _instance;
  MapDataProvider._();

  final NodeDataManager _nodeDataManager = NodeDataManager();

  bool get isOfflineMode => AppState.instance.offlineMode;
  void setOfflineMode(bool enabled) {
    AppState.instance.setOfflineMode(enabled);
  }

  /// Fetch surveillance nodes using the new simplified system.
  /// Returns cached data immediately if available, otherwise fetches from appropriate source.
  Future<List<OsmNode>> getNodes({
    required LatLngBounds bounds,
    required List<NodeProfile> profiles,
    UploadMode uploadMode = UploadMode.production,
    MapSource source = MapSource.auto,
    bool isUserInitiated = false,
  }) async {
    return _nodeDataManager.getNodesFor(
      bounds: bounds,
      profiles: profiles,
      uploadMode: uploadMode,
      isUserInitiated: isUserInitiated,
    );
  }

  /// Bulk node fetch for offline downloads using new system
  Future<List<OsmNode>> getAllNodesForDownload({
    required LatLngBounds bounds,
    required List<NodeProfile> profiles,
    UploadMode uploadMode = UploadMode.production,
    int maxResults = 0, // 0 = no limit for offline downloads
    int maxTries = 3,
  }) async {
    if (AppState.instance.offlineMode) {
      throw OfflineModeException("Cannot fetch remote nodes for offline area download in offline mode.");
    }
    
    // For downloads, always fetch fresh data (don't use cache)
    return _nodeDataManager.fetchWithSplitting(bounds, profiles);
  }

  /// Fetch tile image bytes. Default is to try local first, then remote if not offline. Honors explicit source.
  Future<List<int>> getTile({
    required int z,
    required int x,
    required int y,
    MapSource source = MapSource.auto,
  }) async {
    final offline = AppState.instance.offlineMode;

    // Explicitly remote
    if (source == MapSource.remote) {
      if (offline) {
        throw OfflineModeException("Cannot fetch remote tiles in offline mode.");
      }
      return _fetchRemoteTileFromCurrentProvider(z, x, y);
    }

    // Explicitly local
    if (source == MapSource.local) {
      return fetchLocalTile(z: z, x: x, y: y);
    }

    // AUTO (default): try local first, then remote if not offline
    try {
      return await fetchLocalTile(z: z, x: x, y: y);
    } catch (_) {
      if (!offline) {
        return _fetchRemoteTileFromCurrentProvider(z, x, y);
      } else {
        throw OfflineModeException("Tile $z/$x/$y not found in offline areas and offline mode is enabled.");
      }
    }
  }

  /// Fetch remote tile using current provider from AppState
  Future<List<int>> _fetchRemoteTileFromCurrentProvider(int z, int x, int y) async {
    final appState = AppState.instance;
    final selectedTileType = appState.selectedTileType;
    final selectedProvider = appState.selectedTileProvider;
    
    // We guarantee that a provider and tile type are always selected
    if (selectedTileType == null || selectedProvider == null) {
      throw Exception('No tile provider selected - this should never happen');
    }
    
    final tileUrl = selectedTileType.getTileUrl(z, x, y, apiKey: selectedProvider.apiKey);
    return fetchRemoteTile(z: z, x: x, y: y, url: tileUrl);
  }

  /// Clear any queued tile requests (call when map view changes significantly)
  void clearTileQueue() {
    clearRemoteTileQueue();
  }
  
  /// Clear only tile requests that are no longer visible in the current bounds
  void clearTileQueueSelective(LatLngBounds currentBounds) {
    clearRemoteTileQueueSelective(currentBounds);
  }

  /// Add or update nodes in cache (for upload queue integration)
  void addOrUpdateNodes(List<OsmNode> nodes) {
    _nodeDataManager.addOrUpdateNodes(nodes);
  }

  /// NodeCache compatibility - alias for addOrUpdateNodes
  void addOrUpdate(List<OsmNode> nodes) {
    addOrUpdateNodes(nodes);
  }

  /// Remove node from cache (for deletions)
  void removeNodeById(int nodeId) {
    _nodeDataManager.removeNodeById(nodeId);
  }

  /// Clear cache (when profiles change)
  void clearCache() {
    _nodeDataManager.clearCache();
  }

  /// Force refresh current area (manual retry)
  Future<void> refreshArea({
    required LatLngBounds bounds,
    required List<NodeProfile> profiles,
    UploadMode uploadMode = UploadMode.production,
  }) async {
    return _nodeDataManager.refreshArea(
      bounds: bounds,
      profiles: profiles,
      uploadMode: uploadMode,
    );
  }

  /// NodeCache compatibility methods for upload queue
  /// These all delegate to the singleton cache to ensure consistency
  OsmNode? getNodeById(int nodeId) => NodeSpatialCache().getNodeById(nodeId);
  void removePendingEditMarker(int nodeId) => NodeSpatialCache().removePendingEditMarker(nodeId);
  void removePendingDeletionMarker(int nodeId) => NodeSpatialCache().removePendingDeletionMarker(nodeId);
  void removeTempNodeById(int tempNodeId) => NodeSpatialCache().removeTempNodeById(tempNodeId);
  List<OsmNode> findNodesWithinDistance(LatLng coord, double distanceMeters, {int? excludeNodeId}) => 
      NodeSpatialCache().findNodesWithinDistance(coord, distanceMeters, excludeNodeId: excludeNodeId);

  /// Check if we have good cache coverage for the given area (prevents submission in uncovered areas)
  bool hasGoodCoverageFor(LatLngBounds bounds) => NodeSpatialCache().hasDataFor(bounds);
}