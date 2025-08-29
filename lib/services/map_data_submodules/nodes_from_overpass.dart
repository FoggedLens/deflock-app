import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../models/node_profile.dart';
import '../../models/osm_camera_node.dart';
import '../../app_state.dart';
import '../network_status.dart';

/// Fetches surveillance nodes from the Overpass OSM API for the given bounds and profiles.
Future<List<OsmCameraNode>> fetchOverpassNodes({
  required LatLngBounds bounds,
  required List<NodeProfile> profiles,
  UploadMode uploadMode = UploadMode.production,
  required int maxResults,
}) async {
  if (profiles.isEmpty) return [];
  
  const String overpassEndpoint = 'https://overpass-api.de/api/interpreter';
  
  // Build the Overpass query
  final query = _buildOverpassQuery(bounds, profiles, maxResults);
  
  try {
    debugPrint('[fetchOverpassNodes] Querying Overpass for surveillance nodes...');
    debugPrint('[fetchOverpassNodes] Query:\n$query');
    
    final response = await http.post(
      Uri.parse(overpassEndpoint), 
      body: {'data': query.trim()}
    );
    
    if (response.statusCode != 200) {
      debugPrint('[fetchOverpassNodes] Overpass API error: ${response.body}');
      NetworkStatus.instance.reportOverpassIssue();
      return [];
    }
    
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final elements = data['elements'] as List<dynamic>;
    
    if (elements.length > 20) {
      debugPrint('[fetchOverpassNodes] Retrieved ${elements.length} surveillance nodes');
    }
    
    NetworkStatus.instance.reportOverpassSuccess();
    
    return elements.whereType<Map<String, dynamic>>().map((element) {
      return OsmCameraNode(
        id: element['id'],
        coord: LatLng(element['lat'], element['lon']),
        tags: Map<String, String>.from(element['tags'] ?? {}),
      );
    }).toList();
    
  } catch (e) {
    debugPrint('[fetchOverpassNodes] Exception: $e');
    
    // Report network issues for connection errors
    if (e.toString().contains('Connection refused') || 
        e.toString().contains('Connection timed out') ||
        e.toString().contains('Connection reset')) {
      NetworkStatus.instance.reportOverpassIssue();
    }
    
    return [];
  }
}

/// Builds an Overpass API query for surveillance nodes matching the given profiles within bounds.
String _buildOverpassQuery(LatLngBounds bounds, List<NodeProfile> profiles, int maxResults) {
  // Build node clauses for each profile
  final nodeClauses = profiles.map((profile) {
    // Convert profile tags to Overpass filter format
    final tagFilters = profile.tags.entries
        .map((entry) => '["${entry.key}"="${entry.value}"]')
        .join();
    
    // Build the node query with tag filters and bounding box
    return 'node$tagFilters(${bounds.southWest.latitude},${bounds.southWest.longitude},${bounds.northEast.latitude},${bounds.northEast.longitude});';
  }).join('\n      ');

  return '''
[out:json][timeout:25];
(
  $nodeClauses
);
out body $maxResults;
''';
}