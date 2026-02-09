import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:xml/xml.dart';

import '../../models/node_profile.dart';
import '../../models/osm_node.dart';
import '../../app_state.dart';
import '../network_status.dart';

/// Fetches surveillance nodes from the direct OSM API using bbox query.
/// This is a fallback for when Overpass is not available (e.g., sandbox mode).
Future<List<OsmNode>> fetchOsmApiNodes({
  required LatLngBounds bounds,
  required List<NodeProfile> profiles,
  UploadMode uploadMode = UploadMode.production,
  required int maxResults,
}) async {
  if (profiles.isEmpty) return [];
  
  try {
    final nodes = await _fetchFromOsmApi(
      bounds: bounds,
      profiles: profiles,
      uploadMode: uploadMode,
      maxResults: maxResults,
    );
    
    return nodes;
  } catch (e) {
    debugPrint('[fetchOsmApiNodes] OSM API operation failed: $e');
    return [];
  }
}

/// Internal method that performs the actual OSM API fetch.
Future<List<OsmNode>> _fetchFromOsmApi({
  required LatLngBounds bounds,
  required List<NodeProfile> profiles,
  UploadMode uploadMode = UploadMode.production,
  required int maxResults,
}) async {
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
      throw Exception('OSM API error: ${response.statusCode} - ${response.body}');
    }
    
    // Parse XML response
    final document = XmlDocument.parse(response.body);
    final nodes = _parseOsmApiResponseWithConstraints(document, profiles, maxResults);
    
    if (nodes.isNotEmpty) {
      debugPrint('[fetchOsmApiNodes] Retrieved ${nodes.length} matching surveillance nodes');
    }
    
    // Don't report success here - let the top level handle it
    return nodes;
    
  } catch (e) {
    debugPrint('[fetchOsmApiNodes] Exception: $e');
    
    // Don't report status here - let the top level handle it
    rethrow; // Re-throw to let caller handle
  }
}

/// Parse OSM API XML response to create OsmNode objects with constraint information.
List<OsmNode> _parseOsmApiResponseWithConstraints(XmlDocument document, List<NodeProfile> profiles, int maxResults) {
  final surveillanceNodes = <int, Map<String, dynamic>>{};  // nodeId -> node data
  final constrainedNodeIds = <int>{};
  
  // First pass: collect surveillance nodes
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
      surveillanceNodes[id] = {
        'id': id,
        'lat': lat,
        'lon': lon,
        'tags': tags,
      };
    }
  }
  
  // Second pass: identify constrained nodes from ways
  for (final wayElement in document.findAllElements('way')) {
    for (final ndElement in wayElement.findElements('nd')) {
      final ref = int.tryParse(ndElement.getAttribute('ref') ?? '');
      if (ref != null && surveillanceNodes.containsKey(ref)) {
        constrainedNodeIds.add(ref);
      }
    }
  }
  
  // Third pass: identify constrained nodes from relations
  for (final relationElement in document.findAllElements('relation')) {
    for (final memberElement in relationElement.findElements('member')) {
      if (memberElement.getAttribute('type') == 'node') {
        final ref = int.tryParse(memberElement.getAttribute('ref') ?? '');
        if (ref != null && surveillanceNodes.containsKey(ref)) {
          constrainedNodeIds.add(ref);
        }
      }
    }
  }
  
  // Create OsmNode objects with constraint information
  final nodes = <OsmNode>[];
  for (final nodeData in surveillanceNodes.values) {
    final nodeId = nodeData['id'] as int;
    final isConstrained = constrainedNodeIds.contains(nodeId);
    
    nodes.add(OsmNode(
      id: nodeId,
      coord: LatLng(nodeData['lat'], nodeData['lon']),
      tags: nodeData['tags'] as Map<String, String>,
      isConstrained: isConstrained,
    ));
    
    // Respect maxResults limit if set
    if (maxResults > 0 && nodes.length >= maxResults) {
      break;
    }
  }
  
  final constrainedCount = nodes.where((n) => n.isConstrained).length;
  if (constrainedCount > 0) {
    debugPrint('[fetchOsmApiNodes] Found $constrainedCount constrained nodes out of ${nodes.length} total');
  }
  
  return nodes;
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
  // Skip empty values as they are for refinement purposes only
  for (final entry in profile.tags.entries) {
    if (entry.value.trim().isEmpty) {
      continue; // Skip empty values - they don't need to match anything
    }
    if (nodeTags[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}