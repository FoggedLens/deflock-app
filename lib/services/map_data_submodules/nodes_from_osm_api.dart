import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:xml/xml.dart';

import '../../models/node_profile.dart';
import '../../models/osm_camera_node.dart';
import '../../app_state.dart';
import '../network_status.dart';

/// Fetches surveillance nodes from the direct OSM API using bbox query.
/// This is a fallback for when Overpass is not available (e.g., sandbox mode).
Future<List<OsmCameraNode>> fetchOsmApiNodes({
  required LatLngBounds bounds,
  required List<NodeProfile> profiles,
  UploadMode uploadMode = UploadMode.production,
  required int maxResults,
}) async {
  if (profiles.isEmpty) return [];
  
  // Choose API endpoint based on upload mode
  final String apiHost = uploadMode == UploadMode.sandbox 
      ? 'api06.dev.openstreetmap.org'
      : 'api.openstreetmap.org';
  
  // Build the map query URL - fetches all data in bounding box
  final left = bounds.southWest.longitude;
  final bottom = bounds.southWest.latitude;
  final right = bounds.northEast.longitude;
  final top = bounds.northEast.latitude;
  
  final url = 'https://$apiHost/api/0.6/map?bbox=$left,$bottom,$right,$top';
  
  try {
    debugPrint('[fetchOsmApiNodes] Querying OSM API for nodes in bbox...');
    debugPrint('[fetchOsmApiNodes] URL: $url');
    
    final response = await http.get(Uri.parse(url));
    
    if (response.statusCode != 200) {
      debugPrint('[fetchOsmApiNodes] OSM API error: ${response.statusCode} - ${response.body}');
      NetworkStatus.instance.reportOverpassIssue(); // Reuse same status tracking
      return [];
    }
    
    // Parse XML response
    final document = XmlDocument.parse(response.body);
    final nodes = <OsmCameraNode>[];
    
    // Find all node elements
    for (final nodeElement in document.findAllElements('node')) {
      final id = int.tryParse(nodeElement.getAttribute('id') ?? '');
      final latStr = nodeElement.getAttribute('lat');
      final lonStr = nodeElement.getAttribute('lon');
      
      if (id == null || latStr == null || lonStr == null) continue;
      
      final lat = double.tryParse(latStr);
      final lon = double.tryParse(lonStr);
      if (lat == null || lon == null) continue;
      
      // Parse tags
      final tags = <String, String>{};
      for (final tagElement in nodeElement.findElements('tag')) {
        final key = tagElement.getAttribute('k');
        final value = tagElement.getAttribute('v');
        if (key != null && value != null) {
          tags[key] = value;
        }
      }
      
      // Check if this node matches any of our profiles
      if (_nodeMatchesProfiles(tags, profiles)) {
        nodes.add(OsmCameraNode(
          id: id,
          coord: LatLng(lat, lon),
          tags: tags,
        ));
      }
      
      // Respect maxResults limit if set
      if (maxResults > 0 && nodes.length >= maxResults) {
        break;
      }
    }
    
    if (nodes.isNotEmpty) {
      debugPrint('[fetchOsmApiNodes] Retrieved ${nodes.length} matching surveillance nodes');
    }
    
    NetworkStatus.instance.reportOverpassSuccess(); // Reuse same status tracking
    return nodes;
    
  } catch (e) {
    debugPrint('[fetchOsmApiNodes] Exception: $e');
    
    // Report network issues for connection errors
    if (e.toString().contains('Connection refused') || 
        e.toString().contains('Connection timed out') ||
        e.toString().contains('Connection reset')) {
      NetworkStatus.instance.reportOverpassIssue();
    }
    
    return [];
  }
}

/// Check if a node's tags match any of the given profiles
bool _nodeMatchesProfiles(Map<String, String> nodeTags, List<NodeProfile> profiles) {
  for (final profile in profiles) {
    if (_nodeMatchesProfile(nodeTags, profile)) {
      return true;
    }
  }
  return false;
}

/// Check if a node's tags match a specific profile
bool _nodeMatchesProfile(Map<String, String> nodeTags, NodeProfile profile) {
  // All profile tags must be present in the node for it to match
  for (final entry in profile.tags.entries) {
    if (nodeTags[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}