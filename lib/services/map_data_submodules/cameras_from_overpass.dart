import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../models/camera_profile.dart';
import '../../models/osm_camera_node.dart';
import '../../app_state.dart';

/// Fetches cameras from the Overpass OSM API for the given bounds and profiles.
Future<List<OsmCameraNode>> camerasFromOverpass({
  required LatLngBounds bounds,
  required List<CameraProfile> profiles,
  UploadMode uploadMode = UploadMode.production,
  int? maxCameras,
}) async {
  if (profiles.isEmpty) return [];

  final nodeClauses = profiles.map((profile) {
    final tagFilters = profile.tags.entries
        .map((e) => '["${e.key}"="${e.value}"]')
        .join('\n          ');
    return '''node\n          $tagFilters\n          (${bounds.southWest.latitude},${bounds.southWest.longitude},\n           ${bounds.northEast.latitude},${bounds.northEast.longitude});''';
  }).join('\n      ');

  const String prodEndpoint = 'https://overpass-api.de/api/interpreter';

  final limit = maxCameras ?? AppState.instance.maxCameras;
  final query = '''
    [out:json][timeout:25];
    (
      $nodeClauses
    );
    out body $limit;
  ''';

  try {
    print('[camerasFromOverpass] Querying Overpass...');
    print('[camerasFromOverpass] Query:\n$query');
    final resp = await http.post(Uri.parse(prodEndpoint), body: {'data': query.trim()});
    print('[camerasFromOverpass] Status: ${resp.statusCode}, Length: ${resp.body.length}');
    if (resp.statusCode != 200) {
      print('[camerasFromOverpass] Overpass failed: ${resp.body}');
      return [];
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final elements = data['elements'] as List<dynamic>;
    print('[camerasFromOverpass] Retrieved elements: ${elements.length}');
    return elements.whereType<Map<String, dynamic>>().map((e) {
      return OsmCameraNode(
        id: e['id'],
        coord: LatLng(e['lat'], e['lon']),
        tags: Map<String, String>.from(e['tags'] ?? {}),
      );
    }).toList();
  } catch (e) {
    print('[camerasFromOverpass] Overpass exception: $e');
    return [];
  }
}
