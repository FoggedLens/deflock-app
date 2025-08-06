import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/camera_profile.dart';
import '../models/osm_camera_node.dart';

import '../app_state.dart';

class OverpassService {
  static const _prodEndpoint = 'https://overpass-api.de/api/interpreter';
  static const _sandboxEndpoint = 'https://overpass-api.dev.openstreetmap.org/api/interpreter';

  // You can pass UploadMode, or use production by default
  Future<List<OsmCameraNode>> fetchCameras(
    LatLngBounds bbox,
    List<CameraProfile> profiles,
    {UploadMode uploadMode = UploadMode.production}
  ) async {
    if (profiles.isEmpty) return [];

    // Build one node query per enabled profile (each with all its tags required)
    final nodeClauses = profiles.map((profile) {
      final tagFilters = profile.tags.entries
          .map((e) => '["${e.key}"="${e.value}"]')
          .join('\n          ');
      return '''node\n          $tagFilters\n          (${bbox.southWest.latitude},${bbox.southWest.longitude},\n           ${bbox.northEast.latitude},${bbox.northEast.longitude});''';
    }).join('\n      ');

    final query = '''
      [out:json][timeout:25];
      (
        $nodeClauses
      );
      out body 250;
    ''';

    Future<List<OsmCameraNode>> fetchFromUri(String endpoint, String query) async {
      try {
        print('[Overpass] Querying $endpoint');
        print('[Overpass] Query:\n$query');
        final resp = await http.post(Uri.parse(endpoint), body: {'data': query.trim()});
        print('[Overpass] Status: \\${resp.statusCode}, Length: \\${resp.body.length}');
        if (resp.statusCode != 200) {
          print('[Overpass] Failed: \\${resp.body}');
          return [];
        }
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final elements = data['elements'] as List<dynamic>;
        print('[Overpass] Retrieved elements: \\${elements.length}');
        return elements.whereType<Map<String, dynamic>>().map((e) {
          return OsmCameraNode(
            id: e['id'],
            coord: LatLng(e['lat'], e['lon']),
            tags: Map<String, String>.from(e['tags'] ?? {}),
          );
        }).toList();
      } catch (e) {
        print('[Overpass] Exception: \\${e}');
        // Network error – return empty list silently
        return [];
      }
    }

    // Fetch from production Overpass for all modes.
    return await fetchFromUri(_prodEndpoint, query);
  }
}

