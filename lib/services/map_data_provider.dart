import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/foundation.dart';

import '../models/node_profile.dart';
import '../models/osm_camera_node.dart';
import '../app_state.dart';
import 'map_data_submodules/nodes_from_overpass.dart';
import 'map_data_submodules/tiles_from_remote.dart';
import 'map_data_submodules/nodes_from_local.dart';
import 'map_data_submodules/tiles_from_local.dart';

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

  // REMOVED: AppState get _appState => AppState();

  bool get isOfflineMode => AppState.instance.offlineMode;
  void setOfflineMode(bool enabled) {
    AppState.instance.setOfflineMode(enabled);
  }

  /// Fetch surveillance nodes from OSM/Overpass or local storage.
  /// Remote is default. If source is MapSource.auto, remote is tried first unless offline.
  Future<List<OsmCameraNode>> getNodes({
    required LatLngBounds bounds,
    required List<NodeProfile> profiles,
    UploadMode uploadMode = UploadMode.production,
    MapSource source = MapSource.auto,
  }) async {
    final offline = AppState.instance.offlineMode;

    // Explicit remote request: error if offline, else always remote
    if (source == MapSource.remote) {
      if (offline) {
        throw OfflineModeException("Cannot fetch remote nodes in offline mode.");
      }
      return fetchOverpassNodes(
        bounds: bounds,
        profiles: profiles,
        uploadMode: uploadMode,
        maxResults: AppState.instance.maxCameras,
      );
    }

    // Explicit local request: always use local
    if (source == MapSource.local) {
      return fetchLocalNodes(
        bounds: bounds,
        profiles: profiles,
      );
    }

    // AUTO: default = remote first, fallback to local only if offline
    if (offline) {
      return fetchLocalNodes(
        bounds: bounds,
        profiles: profiles,
        maxNodes: AppState.instance.maxCameras,
      );
    } else {
      // Try remote, fallback to local ONLY if remote throws (optional, could be removed for stricter behavior)
      try {
        return await fetchOverpassNodes(
          bounds: bounds,
          profiles: profiles,
          uploadMode: uploadMode,
          maxResults: AppState.instance.maxCameras,
        );
      } catch (e) {
        debugPrint('[MapDataProvider] Remote node fetch failed, error: $e. Falling back to local.');
      return fetchLocalNodes(
        bounds: bounds,
        profiles: profiles,
        maxNodes: AppState.instance.maxCameras,
      );
      }
    }
  }

  /// Bulk/paged node fetch for offline downloads (handling paging, dedup, and Overpass retries)
  /// Only use for offline area download, not for map browsing! Ignores maxCameras config.
  Future<List<OsmCameraNode>> getAllNodesForDownload({
    required LatLngBounds bounds,
    required List<NodeProfile> profiles,
    UploadMode uploadMode = UploadMode.production,
    int pageSize = 500,
    int maxTries = 3,
  }) async {
    final offline = AppState.instance.offlineMode;
    if (offline) {
      throw OfflineModeException("Cannot fetch remote nodes for offline area download in offline mode.");
    }
    return fetchOverpassNodes(
      bounds: bounds,
      profiles: profiles,
      uploadMode: uploadMode,
      maxResults: pageSize,
    );
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
}