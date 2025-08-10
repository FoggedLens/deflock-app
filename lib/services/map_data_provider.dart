import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/camera_profile.dart';
import '../models/osm_camera_node.dart';
import '../app_state.dart';
import 'map_data_submodules/cameras_from_overpass.dart';
import 'map_data_submodules/tiles_from_osm.dart';
import 'map_data_submodules/cameras_from_local.dart';
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

  /// Fetch cameras from OSM/Overpass or local storage.
  /// Remote is default. If source is MapSource.auto, remote is tried first unless offline.
  Future<List<OsmCameraNode>> getCameras({
    required LatLngBounds bounds,
    required List<CameraProfile> profiles,
    UploadMode uploadMode = UploadMode.production,
    MapSource source = MapSource.auto,
  }) async {
    final offline = AppState.instance.offlineMode;
    print('[MapDataProvider] getCameras called, source=$source, offlineMode=$offline');

    // Explicit remote request: error if offline, else always remote
    if (source == MapSource.remote) {
      if (offline) {
        print('[MapDataProvider] BLOCKED by offlineMode for remote camera fetch');
        throw OfflineModeException("Cannot fetch remote cameras in offline mode.");
      }
      return camerasFromOverpass(
        bounds: bounds,
        profiles: profiles,
        uploadMode: uploadMode,
        maxCameras: AppState.instance.maxCameras,
      );
    }

    // Explicit local request: always use local
    if (source == MapSource.local) {
      return fetchLocalCameras(
        bounds: bounds,
        profiles: profiles,
      );
    }

    // AUTO: default = remote first, fallback to local only if offline
    if (offline) {
      return fetchLocalCameras(
        bounds: bounds,
        profiles: profiles,
      );
    } else {
      // Try remote, fallback to local ONLY if remote throws (optional, could be removed for stricter behavior)
      try {
        return await camerasFromOverpass(
          bounds: bounds,
          profiles: profiles,
          uploadMode: uploadMode,
          maxCameras: AppState.instance.maxCameras,
        );
      } catch (e) {
        print('[MapDataProvider] Remote camera fetch failed, error: $e. Falling back to local.');
        return fetchLocalCameras(
          bounds: bounds,
          profiles: profiles,
        );
      }
    }
  }
  /// Fetch tile image bytes. Default is to try local first, then remote if not offline. Honors explicit source.
  Future<List<int>> getTile({
    required int z,
    required int x,
    required int y,
    MapSource source = MapSource.auto,
  }) async {
    final offline = AppState.instance.offlineMode;
    print('[MapDataProvider] getTile called for $z/$x/$y, source=$source, offlineMode=$offline');

    // Explicitly remote
    if (source == MapSource.remote) {
      if (offline) {
        print('[MapDataProvider] BLOCKED by offlineMode for remote tile fetch');
        throw OfflineModeException("Cannot fetch remote tiles in offline mode.");
      }
      return fetchOSMTile(z: z, x: x, y: y);
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
        return fetchOSMTile(z: z, x: x, y: y);
      } else {
        throw OfflineModeException("Tile $z/$x/$y not found in offline areas and offline mode is enabled.");
      }
    }
  }
}