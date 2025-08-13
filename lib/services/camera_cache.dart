import 'package:latlong2/latlong.dart';
import '../models/osm_camera_node.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;

class CameraCache {
  // Singleton instance
  static final CameraCache instance = CameraCache._internal();
  factory CameraCache() => instance;
  CameraCache._internal();

  final Map<int, OsmCameraNode> _nodes = {};

  /// Add or update a batch of camera nodes in the cache.
  void addOrUpdate(List<OsmCameraNode> nodes) {
    for (var node in nodes) {
      _nodes[node.id] = node;
    }
  }

  /// Query for all cached cameras currently within the given LatLngBounds.
  List<OsmCameraNode> queryByBounds(LatLngBounds bounds) {
    return _nodes.values
        .where((node) => _inBounds(node.coord, bounds))
        .toList();
  }

  /// Retrieve all cached cameras.
  List<OsmCameraNode> getAll() => _nodes.values.toList();

  /// Optionally clear the cache (rarely needed)
  void clear() => _nodes.clear();

  /// Utility: point-in-bounds for coordinates
  bool _inBounds(LatLng coord, LatLngBounds bounds) {
    return coord.latitude >= bounds.southWest.latitude &&
        coord.latitude <= bounds.northEast.latitude &&
        coord.longitude >= bounds.southWest.longitude &&
        coord.longitude <= bounds.northEast.longitude;
  }
}
