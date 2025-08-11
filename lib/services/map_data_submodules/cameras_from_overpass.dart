import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../models/camera_profile.dart';
import '../../models/osm_camera_node.dart';
import '../../app_state.dart';

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
    final query = '''
      [out:json][timeout:25];
      (
        $nodeClauses
      );
      out body $pageSize;
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

  if (!fetchAllPages) {
    // Just one page
    return await fetchChunk();
  } else {
    // Fetch all possible data, paging with deduplication and backoff
    final seenIds = <int>{};
    final allCameras = <OsmCameraNode>[];
    int page = 0;
    while (true) {
      page++;
      List<OsmCameraNode> pageCameras = [];
      int tries = 0;
      while (tries < maxTries) {
        try {
          final cams = await fetchChunk();
          pageCameras = cams.where((c) => !seenIds.contains(c.id)).toList();
          break;
        } catch (e) {
          tries++;
          final delayMs = 400 * (1 << tries);
          print('[camerasFromOverpass][paged] Error on page $page try $tries: $e. Retrying in ${delayMs}ms.');
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      }
      if (pageCameras.isEmpty) break;
      print('[camerasFromOverpass][paged] Page $page: got ${pageCameras.length} new cameras.');
      allCameras.addAll(pageCameras);
      seenIds.addAll(pageCameras.map((c) => c.id));
      if (pageCameras.length < pageSize) break;
    }
    print('[camerasFromOverpass][paged] DONE. Found ${allCameras.length} cameras for download.');
    return allCameras;
  }
}
