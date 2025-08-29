import 'dart:io';
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import '../../models/osm_camera_node.dart';
import '../../models/node_profile.dart';
import '../offline_area_service.dart';
import '../offline_areas/offline_area_models.dart';

/// Fetch surveillance nodes from all offline areas intersecting the bounds/profile list.
Future<List<OsmCameraNode>> fetchLocalNodes({
  required LatLngBounds bounds,
  required List<NodeProfile> profiles,
  int? maxNodes,
}) async {
  final areas = OfflineAreaService().offlineAreas;
  final Map<int, OsmCameraNode> deduped = {};

  for (final area in areas) {
    if (area.status != OfflineAreaStatus.complete) continue;
    if (!area.bounds.isOverlapping(bounds)) continue;

    final nodes = await _loadAreaNodes(area);
    for (final node in nodes) {
      // Deduplicate by node ID, preferring the first occurrence
      if (deduped.containsKey(node.id)) continue;
      // Within view bounds?
      if (!_pointInBounds(node.coord, bounds)) continue;
      // Profile filter if used
      if (profiles.isNotEmpty && !_matchesAnyProfile(node, profiles)) continue;
      deduped[node.id] = node;
    }
  }

  final out = deduped.values.take(maxNodes ?? deduped.length).toList();
  return out;
}

// Try in-memory first, else load from disk
Future<List<OsmCameraNode>> _loadAreaNodes(OfflineArea area) async {
  if (area.cameras.isNotEmpty) {
    return area.cameras;
  }
  final file = File('${area.directory}/cameras.json');
  if (await file.exists()) {
    final str = await file.readAsString();
    final jsonList = jsonDecode(str) as List;
    return jsonList.map((e) => OsmCameraNode.fromJson(e)).toList();
  }
  return [];
}

bool _pointInBounds(LatLng pt, LatLngBounds bounds) {
  return pt.latitude  >= bounds.southWest.latitude &&
         pt.latitude  <= bounds.northEast.latitude &&
         pt.longitude >= bounds.southWest.longitude &&
         pt.longitude <= bounds.northEast.longitude;
}

bool _matchesAnyProfile(OsmCameraNode node, List<NodeProfile> profiles) {
  for (final prof in profiles) {
    if (_nodeMatchesProfile(node, prof)) return true;
  }
  return false;
}

bool _nodeMatchesProfile(OsmCameraNode node, NodeProfile profile) {
  for (final e in profile.tags.entries) {
    if (node.tags[e.key] != e.value) return false; // All profile tags must match
  }
  return true;
}
