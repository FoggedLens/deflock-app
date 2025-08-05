import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/camera_profile.dart';
import '../models/osm_camera_node.dart';

class OverpassService {
  static const _endpoint = 'https://overpass-api.de/api/interpreter';

  Future<List<OsmCameraNode>> fetchCameras(
    LatLngBounds bbox,
    List<CameraProfile> profiles,
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

    try {
      final resp =
          await http.post(Uri.parse(_endpoint), body: {'data': query.trim()});
      if (resp.statusCode != 200) return [];

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final elements = data['elements'] as List<dynamic>;

      return elements.whereType<Map<String, dynamic>>().map((e) {
        return OsmCameraNode(
          id: e['id'],
          coord: LatLng(e['lat'], e['lon']),
          tags: Map<String, String>.from(e['tags'] ?? {}),
        );
      }).toList();
    } catch (_) {
      // Network error – return empty list silently
      return [];
    }
  }
}

