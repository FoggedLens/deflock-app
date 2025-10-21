import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/foundation.dart';

import '../models/node_profile.dart';
import '../models/osm_node.dart';
import '../app_state.dart';
import 'map_data_submodules/nodes_from_overpass.dart';
import 'map_data_submodules/nodes_from_osm_api.dart';
import 'map_data_submodules/tiles_from_remote.dart';
import 'map_data_submodules/nodes_from_local.dart';
import 'map_data_submodules/tiles_from_local.dart';
import 'network_status.dart';
import 'prefetch_area_service.dart';

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
  Future<List<OsmNode>> getNodes({
    required LatLngBounds bounds,
    required List<NodeProfile> profiles,
    UploadMode uploadMode = UploadMode.production,
    MapSource source = MapSource.auto,
  }) async {
    try {
    final offline = AppState.instance.offlineMode;

    // Explicit remote request: error if offline, else always remote
    if (source == MapSource.remote) {
      if (offline) {
        throw OfflineModeException("Cannot fetch remote nodes in offline mode.");
      }
      return _fetchRemoteNodes(
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

    // AUTO: In offline mode, behavior depends on upload mode
    if (offline) {
      if (uploadMode == UploadMode.sandbox) {
        // Offline + Sandbox = no nodes (local cache is production data)
        debugPrint('[MapDataProvider] Offline + Sandbox mode: returning no nodes (local cache is production data)');
        return <OsmNode>[];
      } else {
        // Offline + Production = use local cache
        return fetchLocalNodes(
          bounds: bounds,
          profiles: profiles,
          maxNodes: AppState.instance.maxCameras,
        );
      }
    } else if (uploadMode == UploadMode.sandbox) {
      // Sandbox mode: Only fetch from sandbox API, ignore local production nodes
      debugPrint('[MapDataProvider] Sandbox mode: fetching only from sandbox API, ignoring local cache');
      return _fetchRemoteNodes(
        bounds: bounds,
        profiles: profiles,
        uploadMode: uploadMode,
        maxResults: AppState.instance.maxCameras,
      );
    } else {
      // Production mode: use pre-fetch service for efficient area loading
      final preFetchService = PrefetchAreaService();
      
      // Always get local nodes first (fast, from cache)
      final localNodes = await fetchLocalNodes(
        bounds: bounds,
        profiles: profiles,
        maxNodes: AppState.instance.maxCameras,
      );
      
      // Check if we need to trigger a new pre-fetch
      if (!preFetchService.isWithinPreFetchedArea(bounds, profiles, uploadMode)) {
        // Outside pre-fetched area - trigger new pre-fetch but don't wait for it
        debugPrint('[MapDataProvider] Outside pre-fetched area, triggering new pre-fetch');
        preFetchService.requestPreFetchIfNeeded(
          viewBounds: bounds,
          profiles: profiles,
          uploadMode: uploadMode,
        );
      } else {
        debugPrint('[MapDataProvider] Using existing pre-fetched area cache');
      }
      
      // Apply rendering limit and warn if nodes are being excluded
      final maxNodes = AppState.instance.maxCameras;
      if (localNodes.length > maxNodes) {
        NetworkStatus.instance.reportNodeLimitReached(localNodes.length, maxNodes);
      }
      
      return localNodes.take(maxNodes).toList();
    }
    } finally {
      // Always report node completion, regardless of success or failure
      NetworkStatus.instance.reportNodeComplete();
    }
  }

  /// Bulk/paged node fetch for offline downloads (handling paging, dedup, and Overpass retries)
  /// Only use for offline area download, not for map browsing! Ignores maxCameras config.
  Future<List<OsmNode>> getAllNodesForDownload({
    required LatLngBounds bounds,
    required List<NodeProfile> profiles,
    UploadMode uploadMode = UploadMode.production,
    int maxResults = 0, // 0 = no limit for offline downloads
    int maxTries = 3,
  }) async {
    final offline = AppState.instance.offlineMode;
    if (offline) {
      throw OfflineModeException("Cannot fetch remote nodes for offline area download in offline mode.");
    }
    return _fetchRemoteNodes(
      bounds: bounds,
      profiles: profiles,
      uploadMode: uploadMode,
      maxResults: maxResults, // Pass 0 for unlimited
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
  
  /// Clear only tile requests that are no longer visible in the current bounds
  void clearTileQueueSelective(LatLngBounds currentBounds) {
    clearRemoteTileQueueSelective(currentBounds);
  }

  /// Fetch remote nodes with Overpass first, OSM API fallback
  Future<List<OsmNode>> _fetchRemoteNodes({
    required LatLngBounds bounds,
    required List<NodeProfile> profiles,
    UploadMode uploadMode = UploadMode.production,
    required int maxResults,
  }) async {
    // For sandbox mode, skip Overpass and go directly to OSM API
    // (Overpass doesn't have sandbox data)
    if (uploadMode == UploadMode.sandbox) {
      debugPrint('[MapDataProvider] Sandbox mode detected, using OSM API directly');
      return fetchOsmApiNodes(
        bounds: bounds,
        profiles: profiles,
        uploadMode: uploadMode,
        maxResults: maxResults,
      );
    }

    // For production mode, try Overpass first, then fallback to OSM API
    try {
      final nodes = await fetchOverpassNodes(
        bounds: bounds,
        profiles: profiles,
        uploadMode: uploadMode,
        maxResults: maxResults,
      );
      
      // If Overpass returns nodes, we're good
      if (nodes.isNotEmpty) {
        return nodes;
      }
      
      // If Overpass returns empty (could be no data or could be an issue), 
      // try OSM API as well to be thorough
      debugPrint('[MapDataProvider] Overpass returned no nodes, trying OSM API fallback');
      return fetchOsmApiNodes(
        bounds: bounds,
        profiles: profiles,
        uploadMode: uploadMode,
        maxResults: maxResults,
      );
      
    } catch (e) {
      debugPrint('[MapDataProvider] Overpass failed ($e), trying OSM API fallback');
      return fetchOsmApiNodes(
        bounds: bounds,
        profiles: profiles,
        uploadMode: uploadMode,
        maxResults: maxResults,
      );
    }
  }
}