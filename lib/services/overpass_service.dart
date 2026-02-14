import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/node_profile.dart';
import '../models/osm_node.dart';
import '../dev_config.dart';

/// Simple Overpass API client with proper HTTP retry logic.
/// Single responsibility: Make requests, handle network errors, return data.
class OverpassService {
  static const String _endpoint = 'https://overpass-api.de/api/interpreter';
  final http.Client _client;

  OverpassService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch surveillance nodes from Overpass API with proper retry logic.
  /// Throws NetworkError for retryable failures, NodeLimitError for area splitting.
  Future<List<OsmNode>> fetchNodes({
    required LatLngBounds bounds,
    required List<NodeProfile> profiles,
    int maxRetries = 3,
  }) async {
    if (profiles.isEmpty) return [];
    
    final query = _buildQuery(bounds, profiles);
    
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        debugPrint('[OverpassService] Attempt ${attempt + 1}/${maxRetries + 1} for ${profiles.length} profiles');
        
        final response = await _client.post(
          Uri.parse(_endpoint),
          body: {'data': query},
        ).timeout(kOverpassQueryTimeout);
        
        if (response.statusCode == 200) {
          return _parseResponse(response.body);
        }
        
        // Check for specific error types
        final errorBody = response.body;
        
        // Node limit error - caller should split area
        if (response.statusCode == 400 && 
            (errorBody.contains('too many nodes') && errorBody.contains('50000'))) {
          debugPrint('[OverpassService] Node limit exceeded, area should be split');
          throw NodeLimitError('Query exceeded 50k node limit');
        }
        
        // Timeout error - also try splitting (complex query)
        if (errorBody.contains('timeout') || 
            errorBody.contains('runtime limit exceeded') ||
            errorBody.contains('Query timed out')) {
          debugPrint('[OverpassService] Query timeout, area should be split');
          throw NodeLimitError('Query timed out - area too complex');
        }
        
        // Rate limit - throw immediately, don't retry
        if (response.statusCode == 429 ||
            errorBody.contains('rate limited') ||
            errorBody.contains('too many requests')) {
          debugPrint('[OverpassService] Rate limited by Overpass');
          throw RateLimitError('Rate limited by Overpass API');
        }
        
        // Other HTTP errors - retry with backoff
        if (attempt < maxRetries) {
          final delay = Duration(milliseconds: (200 * (1 << attempt)).clamp(200, 5000));
          debugPrint('[OverpassService] HTTP ${response.statusCode} error, retrying in ${delay.inMilliseconds}ms');
          await Future.delayed(delay);
          continue;
        }
        
        throw NetworkError('HTTP ${response.statusCode}: $errorBody');
        
      } catch (e) {
        // Handle specific error types without retry
        if (e is NodeLimitError || e is RateLimitError) {
          rethrow;
        }
        
        // Network/timeout errors - retry with backoff
        if (attempt < maxRetries) {
          final delay = Duration(milliseconds: (200 * (1 << attempt)).clamp(200, 5000));
          debugPrint('[OverpassService] Network error ($e), retrying in ${delay.inMilliseconds}ms');
          await Future.delayed(delay);
          continue;
        }
        
        throw NetworkError('Network error after $maxRetries retries: $e');
      }
    }
    
    throw NetworkError('Max retries exceeded');
  }
  
  /// Build Overpass QL query for given bounds and profiles
  String _buildQuery(LatLngBounds bounds, List<NodeProfile> profiles) {
    final nodeClauses = profiles.map((profile) {
      // Convert profile tags to Overpass filter format, excluding empty values
      final tagFilters = profile.tags.entries
          .where((entry) => entry.value.trim().isNotEmpty)
          .map((entry) => '["${entry.key}"="${entry.value}"]')
          .join();
      
      return 'node$tagFilters(${bounds.southWest.latitude},${bounds.southWest.longitude},${bounds.northEast.latitude},${bounds.northEast.longitude});';
    }).join('\n  ');

    return '''
[out:json][timeout:${kOverpassQueryTimeout.inSeconds}];
(
  $nodeClauses
);
out body;
(
  way(bn);
  rel(bn);  
);
out skel;
''';
  }
  
  /// Parse Overpass JSON response into OsmNode objects
  List<OsmNode> _parseResponse(String responseBody) {
    final data = jsonDecode(responseBody) as Map<String, dynamic>;
    final elements = data['elements'] as List<dynamic>;
    
    final nodeElements = <Map<String, dynamic>>[];
    final constrainedNodeIds = <int>{};
    
    // First pass: collect surveillance nodes and identify constrained nodes
    for (final element in elements.whereType<Map<String, dynamic>>()) {
      final type = element['type'] as String?;
      
      if (type == 'node') {
        nodeElements.add(element);
      } else if (type == 'way' || type == 'relation') {
        // Mark referenced nodes as constrained
        final refs = element['nodes'] as List<dynamic>? ?? 
                     element['members']?.where((m) => m['type'] == 'node').map((m) => m['ref']) ?? [];
        
        for (final ref in refs) {
          final nodeId = ref is int ? ref : int.tryParse(ref.toString());
          if (nodeId != null) constrainedNodeIds.add(nodeId);
        }
      }
    }
    
    // Second pass: create OsmNode objects
    final nodes = nodeElements.map((element) {
      final nodeId = element['id'] as int;
      return OsmNode(
        id: nodeId,
        coord: LatLng(element['lat'], element['lon']),
        tags: Map<String, String>.from(element['tags'] ?? {}),
        isConstrained: constrainedNodeIds.contains(nodeId),
      );
    }).toList();
    
    debugPrint('[OverpassService] Parsed ${nodes.length} nodes, ${constrainedNodeIds.length} constrained');
    return nodes;
  }
}

/// Error thrown when query exceeds node limits or is too complex - area should be split
class NodeLimitError extends Error {
  final String message;
  NodeLimitError(this.message);
  @override
  String toString() => 'NodeLimitError: $message';
}

/// Error thrown when rate limited - should not retry immediately
class RateLimitError extends Error {
  final String message;
  RateLimitError(this.message);
  @override
  String toString() => 'RateLimitError: $message';
}

/// Error thrown for network/HTTP issues - retryable
class NetworkError extends Error {
  final String message;
  NetworkError(this.message);
  @override
  String toString() => 'NetworkError: $message';
}