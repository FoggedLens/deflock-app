import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/camera_profile.dart';
import '../models/osm_camera_node.dart';
import '../app_state.dart';
import 'map_data_submodules/cameras_from_overpass.dart';
import 'map_data_submodules/tiles_from_osm.dart';

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

  AppState get _appState => AppState(); // Use singleton for now

  bool get isOfflineMode => _appState.offlineMode;
  void setOfflineMode(bool enabled) {
    _appState.setOfflineMode(enabled);
  }

  /// Fetch cameras from OSM/Overpass or local storage, depending on source/offline mode.
  Future<List<OsmCameraNode>> getCameras({
    required LatLngBounds bounds,
    required List<CameraProfile> profiles,
    UploadMode uploadMode = UploadMode.production,
    MapSource source = MapSource.auto,
  }) async {
    print('[MapDataProvider] getCameras called, source=$source, offlineMode=$isOfflineMode');
    // Resolve source:
    if (isOfflineMode && source != MapSource.local) {
      print('[MapDataProvider] BLOCKED by offlineMode for getCameras');
      throw OfflineModeException("Cannot fetch remote cameras in offline mode.");
    }
    if (source == MapSource.local) {
      // TODO: implement local camera loading
      throw UnimplementedError('Local camera loading not yet implemented.');
    } else {
      // Use Overpass remote fetch, from submodule:
      return camerasFromOverpass(bounds: bounds, profiles: profiles, uploadMode: uploadMode);
    }
  }
  /// Fetch tile image bytes from OSM or local (future). Only fetches, does not save!
  Future<List<int>> getTile({
    required int z,
    required int x,
    required int y,
    MapSource source = MapSource.auto,
  }) async {
    print('[MapDataProvider] getTile called for $z/$x/$y, source=$source, offlineMode=$isOfflineMode');
    if (isOfflineMode && source != MapSource.local) {
      print('[MapDataProvider] BLOCKED by offlineMode for $z/$x/$y');
      throw OfflineModeException("Cannot fetch remote tiles in offline mode.");
    }
    if (source == MapSource.local) {
      // TODO: implement local tile loading
      throw UnimplementedError('Local tile loading not yet implemented.');
    } else {
      // Use OSM remote fetch from submodule:
      return fetchOSMTile(z: z, x: x, y: y);
    }
  }
}