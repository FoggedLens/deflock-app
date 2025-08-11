import 'dart:io';
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import '../../models/osm_camera_node.dart';
import '../../models/camera_profile.dart';
import '../offline_area_service.dart';
import '../offline_areas/offline_area_models.dart';

/// Fetch camera nodes from all offline areas intersecting the bounds/profile list.
Future<List<OsmCameraNode>> fetchLocalCameras({
  required LatLngBounds bounds,
  required List<CameraProfile> profiles,
  int? maxCameras,
}) async {
  final areas = OfflineAreaService().offlineAreas;
  final Map<int, OsmCameraNode> deduped = {};

  for (final area in areas) {
    if (area.status != OfflineAreaStatus.complete) continue;
    if (!area.bounds.isOverlapping(bounds)) continue;

    final nodes = await _loadAreaCameras(area);
    for (final cam in nodes) {
      // Deduplicate by camera ID, preferring the first occurrence
      if (deduped.containsKey(cam.id)) continue;
      // Within view bounds?
      if (!_pointInBounds(cam.coord, bounds)) continue;
      // Profile filter if used
      if (profiles.isNotEmpty && !_matchesAnyProfile(cam, profiles)) continue;
      deduped[cam.id] = cam;
    }
  }

  final out = deduped.values.take(maxCameras ?? deduped.length).toList();
  return out;
}

// Try in-memory first, else load from disk
Future<List<OsmCameraNode>> _loadAreaCameras(OfflineArea area) async {
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

bool _matchesAnyProfile(OsmCameraNode cam, List<CameraProfile> profiles) {
  for (final prof in profiles) {
    if (_cameraMatchesProfile(cam, prof)) return true;
  }
  return false;
}

bool _cameraMatchesProfile(OsmCameraNode cam, CameraProfile profile) {
  for (final e in profile.tags.entries) {
    if (cam.tags[e.key] != e.value) return false; // All profile tags must match
  }
  return true;
}
