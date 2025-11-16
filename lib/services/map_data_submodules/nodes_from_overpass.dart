import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../models/node_profile.dart';
import '../../models/osm_node.dart';
import '../../models/pending_upload.dart';
import '../../app_state.dart';
import '../../dev_config.dart';
import '../network_status.dart';
import '../overpass_node_limit_exception.dart';

/// Fetches surveillance nodes from the Overpass OSM API for the given bounds and profiles.
/// If the query fails due to too many nodes, automatically splits the area and retries.
Future<List<OsmNode>> fetchOverpassNodes({
  required LatLngBounds bounds,
  required List<NodeProfile> profiles,
  UploadMode uploadMode = UploadMode.production,
  required int maxResults,
}) async {
  // Check if this is a user-initiated fetch (indicated by loading state)
  final wasUserInitiated = NetworkStatus.instance.currentStatus == NetworkStatusType.waiting;
  
  return _fetchOverpassNodesWithSplitting(
    bounds: bounds,
    profiles: profiles,
    uploadMode: uploadMode,
    maxResults: maxResults,
    splitDepth: 0,
    wasUserInitiated: wasUserInitiated,
  );
}

/// Internal method that handles splitting when node limit is exceeded.
Future<List<OsmNode>> _fetchOverpassNodesWithSplitting({
  required LatLngBounds bounds,
  required List<NodeProfile> profiles,
  UploadMode uploadMode = UploadMode.production,
  required int maxResults,
  required int splitDepth,
  required bool wasUserInitiated,
}) async {
  if (profiles.isEmpty) return [];
  
  const int maxSplitDepth = kMaxPreFetchSplitDepth; // Maximum times we'll split (4^3 = 64 max sub-areas)
  
  try {
    return await _fetchSingleOverpassQuery(
      bounds: bounds,
      profiles: profiles,
      maxResults: maxResults,
    );
  } on OverpassRateLimitException catch (e) {
    // Rate limits should NOT be split - just fail with extended backoff
    debugPrint('[fetchOverpassNodes] Rate limited - using extended backoff, not splitting');
    
    // Report error if user was waiting
    if (wasUserInitiated) {
      NetworkStatus.instance.setNetworkError();
    }
    
    // Wait longer for rate limits before giving up entirely  
    await Future.delayed(const Duration(seconds: 30));
    return []; // Return empty rather than rethrowing
  } on OverpassNodeLimitException {
    // If we've hit max split depth, give up to avoid infinite recursion
    if (splitDepth >= maxSplitDepth) {
      debugPrint('[fetchOverpassNodes] Max split depth reached, giving up on area: $bounds');
      // Report timeout if this was user-initiated (can't split further)
      if (wasUserInitiated) {
        NetworkStatus.instance.setTimeoutError();
      }
      return [];
    }
    
    // Split the bounds into 4 quadrants and try each separately
    debugPrint('[fetchOverpassNodes] Splitting area into quadrants (depth: $splitDepth)');
    final quadrants = _splitBounds(bounds);
    final List<OsmNode> allNodes = [];
    
    for (final quadrant in quadrants) {
      final nodes = await _fetchOverpassNodesWithSplitting(
        bounds: quadrant,
        profiles: profiles,
        uploadMode: uploadMode,
        maxResults: 0, // No limit on individual quadrants to avoid double-limiting
        splitDepth: splitDepth + 1,
        wasUserInitiated: wasUserInitiated,
      );
      allNodes.addAll(nodes);
    }
    
    debugPrint('[fetchOverpassNodes] Collected ${allNodes.length} nodes from ${quadrants.length} quadrants');
    return allNodes;
  }
}

/// Perform a single Overpass query without splitting logic.
Future<List<OsmNode>> _fetchSingleOverpassQuery({
  required LatLngBounds bounds,
  required List<NodeProfile> profiles,
  required int maxResults,
}) async {
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
      final errorBody = response.body;
      debugPrint('[fetchOverpassNodes] Overpass API error: $errorBody');
      
      // Check if it's specifically the 50k node limit error (HTTP 400)
      // Exact message: "You requested too many nodes (limit is 50000)"
      if (errorBody.contains('too many nodes') && 
          errorBody.contains('50000')) {
        debugPrint('[fetchOverpassNodes] Detected 50k node limit error, will attempt splitting');
        throw OverpassNodeLimitException('Query exceeded node limit', serverResponse: errorBody);
      }
      
      // Check for timeout errors that indicate query complexity (should split)
      // Common timeout messages from Overpass
      if (errorBody.contains('timeout') || 
          errorBody.contains('runtime limit exceeded') ||
          errorBody.contains('Query timed out')) {
        debugPrint('[fetchOverpassNodes] Detected timeout error, will attempt splitting to reduce complexity');
        throw OverpassNodeLimitException('Query timed out', serverResponse: errorBody);
      }
      
      // Check for rate limiting (should NOT split - needs longer backoff)
      if (errorBody.contains('rate limited') || 
          errorBody.contains('too many requests') ||
          response.statusCode == 429) {
        debugPrint('[fetchOverpassNodes] Rate limited by Overpass API - needs extended backoff');
        throw OverpassRateLimitException('Rate limited by server', serverResponse: errorBody);
      }
      
      NetworkStatus.instance.reportOverpassIssue();
      return [];
    }
    
    final data = await compute(jsonDecode, response.body) as Map<String, dynamic>;
    final elements = data['elements'] as List<dynamic>;
    
    if (elements.length > 20) {
      debugPrint('[fetchOverpassNodes] Retrieved ${elements.length} elements (nodes + ways/relations)');
    }
    
    NetworkStatus.instance.reportOverpassSuccess();
    
    // Parse response to determine which nodes are constrained
    final nodes = _parseOverpassResponseWithConstraints(elements);
    
    // Clean up any pending uploads that now appear in Overpass results
    _cleanupCompletedUploads(nodes);
    
    return nodes;
    
  } catch (e) {
    // Re-throw OverpassNodeLimitException so splitting logic can catch it
    if (e is OverpassNodeLimitException) rethrow;
    
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
/// Also fetches ways and relations that reference these nodes to determine constraint status.
String _buildOverpassQuery(LatLngBounds bounds, List<NodeProfile> profiles, int maxResults) {
  // Build node clauses for each profile
  final nodeClauses = profiles.map((profile) {
    // Convert profile tags to Overpass filter format
    final tagFilters = profile.tags.entries
        .map((entry) => '["${entry.key}"="${entry.value}"]')
        .join();
    
    // Build the node query with tag filters and bounding box
    return 'node$tagFilters(${bounds.southWest.latitude},${bounds.southWest.longitude},${bounds.northEast.latitude},${bounds.northEast.longitude});';
  }).join('\n  ');

  return '''
[out:json][timeout:25];
(
  $nodeClauses
);
out body ${maxResults > 0 ? maxResults : ''};
(
  way(bn);
  rel(bn);  
);
out meta;
''';
}

/// Split a LatLngBounds into 4 quadrants (NW, NE, SW, SE).
List<LatLngBounds> _splitBounds(LatLngBounds bounds) {
  final centerLat = (bounds.north + bounds.south) / 2;
  final centerLng = (bounds.east + bounds.west) / 2;
  
  return [
    // Southwest quadrant (bottom-left)
    LatLngBounds(
      LatLng(bounds.south, bounds.west),
      LatLng(centerLat, centerLng),
    ),
    // Southeast quadrant (bottom-right)
    LatLngBounds(
      LatLng(bounds.south, centerLng),
      LatLng(centerLat, bounds.east),
    ),
    // Northwest quadrant (top-left)
    LatLngBounds(
      LatLng(centerLat, bounds.west),
      LatLng(bounds.north, centerLng),
    ),
    // Northeast quadrant (top-right)
    LatLngBounds(
      LatLng(centerLat, centerLng),
      LatLng(bounds.north, bounds.east),
    ),
  ];
}

/// Parse Overpass response elements to create OsmNode objects with constraint information.
List<OsmNode> _parseOverpassResponseWithConstraints(List<dynamic> elements) {
  final nodeElements = <Map<String, dynamic>>[];
  final constrainedNodeIds = <int>{};
  
  // First pass: collect surveillance nodes and identify constrained nodes
  for (final element in elements.whereType<Map<String, dynamic>>()) {
    final type = element['type'] as String?;
    
    if (type == 'node') {
      // This is a surveillance node - collect it
      nodeElements.add(element);
    } else if (type == 'way' || type == 'relation') {
      // This is a way/relation that references some of our nodes
      final refs = element['nodes'] as List<dynamic>? ?? 
                   element['members']?.where((m) => m['type'] == 'node').map((m) => m['ref']) ?? [];
      
      // Mark all referenced nodes as constrained
      for (final ref in refs) {
        if (ref is int) {
          constrainedNodeIds.add(ref);
        } else if (ref is String) {
          final nodeId = int.tryParse(ref);
          if (nodeId != null) constrainedNodeIds.add(nodeId);
        }
      }
    }
  }
  
  // Second pass: create OsmNode objects with constraint info
  final nodes = nodeElements.map((element) {
    final nodeId = element['id'] as int;
    final isConstrained = constrainedNodeIds.contains(nodeId);
    
    return OsmNode(
      id: nodeId,
      coord: LatLng(element['lat'], element['lon']),
      tags: Map<String, String>.from(element['tags'] ?? {}),
      isConstrained: isConstrained,
    );
  }).toList();
  
  final constrainedCount = nodes.where((n) => n.isConstrained).length;
  if (constrainedCount > 0) {
    debugPrint('[fetchOverpassNodes] Found $constrainedCount constrained nodes out of ${nodes.length} total');
  }
  
  return nodes;
}

/// Clean up pending uploads that now appear in Overpass results
void _cleanupCompletedUploads(List<OsmNode> overpassNodes) {
  try {
    final appState = AppState.instance;
    final pendingUploads = appState.pendingUploads;
    
    if (pendingUploads.isEmpty) return;
    
    final overpassNodeIds = overpassNodes.map((n) => n.id).toSet();
    
    // Find pending uploads whose submitted node IDs now appear in Overpass results
    final uploadsToRemove = <PendingUpload>[];
    
    for (final upload in pendingUploads) {
      if (upload.submittedNodeId != null && 
          overpassNodeIds.contains(upload.submittedNodeId!)) {
        uploadsToRemove.add(upload);
        debugPrint('[OverpassCleanup] Found submitted node ${upload.submittedNodeId} in Overpass results, removing from pending queue');
      }
    }
    
    // Remove the completed uploads from the queue
    for (final upload in uploadsToRemove) {
      appState.removeFromQueue(upload);
    }
    
    if (uploadsToRemove.isNotEmpty) {
      debugPrint('[OverpassCleanup] Cleaned up ${uploadsToRemove.length} completed uploads');
    }
    
  } catch (e) {
    debugPrint('[OverpassCleanup] Error during cleanup: $e');
    // Don't let cleanup errors break the main functionality
  }
}