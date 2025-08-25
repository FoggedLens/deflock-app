import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../models/camera_profile.dart';
import '../../models/osm_camera_node.dart';
import '../../app_state.dart';
import '../network_status.dart';

/// Fetches cameras from the Overpass OSM API for the given bounds and profiles.
/// If fetchAllPages is true, returns all possible cameras using multiple API calls (paging with pageSize).
/// If false (the default), returns only the first page of up to pageSize results.
Future<List<OsmCameraNode>> camerasFromOverpass({
  required LatLngBounds bounds,
  required List<CameraProfile> profiles,
  UploadMode uploadMode = UploadMode.production,
  int pageSize = 500,           // Used for both default limit and paging chunk
  bool fetchAllPages = false,   // True for offline area download, else just grabs first chunk
  int maxTries = 3,
}) async {
  if (profiles.isEmpty) return [];
  const String prodEndpoint = 'https://overpass-api.de/api/interpreter';

  final nodeClauses = profiles.map((profile) {
    final tagFilters = profile.tags.entries
        .map((e) => '["${e.key}"="${e.value}"]')
        .join('\n          ');
    return '''node\n          $tagFilters\n          (${bounds.southWest.latitude},${bounds.southWest.longitude},\n           ${bounds.northEast.latitude},${bounds.northEast.longitude});''';
  }).join('\n      ');

  // Helper for one Overpass chunk fetch
  Future<List<OsmCameraNode>> fetchChunk() async {
    final outLine = fetchAllPages ? 'out body;' : 'out body $pageSize;';
    final query = '''
      [out:json][timeout:25];
      (
        $nodeClauses
      );
      $outLine
    ''';
    try {
      print('[camerasFromOverpass] Querying Overpass...');
      print('[camerasFromOverpass] Query:\n$query');
      final resp = await http.post(Uri.parse(prodEndpoint), body: {'data': query.trim()});
      // Only log errors
      if (resp.statusCode != 200) {
        debugPrint('[camerasFromOverpass] Overpass failed: ${resp.body}');
        NetworkStatus.instance.reportOverpassIssue();
        return [];
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final elements = data['elements'] as List<dynamic>;
      
      // Only log if many cameras found or if it's a bulk download
      if (elements.length > 20 || fetchAllPages) {
        debugPrint('[camerasFromOverpass] Retrieved ${elements.length} cameras');
      }
      NetworkStatus.instance.reportOverpassSuccess();
      return elements.whereType<Map<String, dynamic>>().map((e) {
        return OsmCameraNode(
          id: e['id'],
          coord: LatLng(e['lat'], e['lon']),
          tags: Map<String, String>.from(e['tags'] ?? {}),
        );
      }).toList();
    } catch (e) {
      print('[camerasFromOverpass] Overpass exception: $e');
      
      // Report network issues on connection errors
      if (e.toString().contains('Connection refused') || 
          e.toString().contains('Connection timed out') ||
          e.toString().contains('Connection reset')) {
        NetworkStatus.instance.reportOverpassIssue();
      }
      
      return [];
    }
  }

  // All paths just use a single fetch now; paging logic no longer required.
  return await fetchChunk();
}
