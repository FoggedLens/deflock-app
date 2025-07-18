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

    // Build regex of surveillance:type values from enabled profiles
    final types = profiles
        .map((p) => p.tags['surveillance:type'])
        .whereType<String>()
        .toSet();
    final regex = types.join('|');

    final query = '''
      [out:json][timeout:25];
      (
        node
          ["man_made"="surveillance"]
          ["surveillance:type"~"^(${regex})\$"]
          (${bbox.southWest.latitude},${bbox.southWest.longitude},
           ${bbox.northEast.latitude},${bbox.northEast.longitude});
      );
      out body 100;
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

