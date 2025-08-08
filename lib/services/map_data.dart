import 'dart:typed_data';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import '../models/osm_camera_node.dart';

/// Central provider for map tiles and camera data, abstracting local/disk and remote/OSM fetches.
class MapDataProvider {
  static final MapDataProvider _instance = MapDataProvider._();
  factory MapDataProvider() => _instance;
  MapDataProvider._();

  /// Returns tile bytes for this tile, or null if unavailable (when [allowRemote] is false and not found offline)
  /// [preferLocal]: try disk cache first
  /// [allowRemote]: if true, will request OSM server if tile not on disk and not in offline mode
  Future<Uint8List?> getTile(int z, int x, int y,
      {bool preferLocal = true, bool allowRemote = true}) async {
    // Scaffold: real logic will go here
    throw UnimplementedError('getTile needs implementation');
  }

  /// Returns camera nodes for a given bounding box.
  /// [preferLocal]: try disk cache first
  /// [allowRemote]: query Overpass if true (and allowed by offline mode)
  Future<List<OsmCameraNode>> getCameras(LatLngBounds bounds,
      {bool preferLocal = false, bool allowRemote = true}) async {
    // Scaffold: real logic will go here
    throw UnimplementedError('getCameras needs implementation');
  }
}
