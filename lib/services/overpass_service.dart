import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/node_profile.dart';
import '../models/osm_node.dart';
import '../dev_config.dart';
import 'http_client.dart';
import 'service_policy.dart';

/// Simple Overpass API client with retry and fallback logic.
/// Single responsibility: Make requests, handle network errors, return data.
class OverpassService {
  static const String defaultEndpoint = 'https://overpass.deflock.org/api/interpreter';
  static const String fallbackEndpoint = 'https://overpass-api.de/api/interpreter';
  static const _policy = ResiliencePolicy(
    maxRetries: 3,
    httpTimeout: Duration(seconds: 45),
  );

  final http.Client _client;
  /// Optional override endpoint. When null, uses defaultEndpoint (or settings override).
  final String? _endpointOverride;

  OverpassService({http.Client? client, String? endpoint})
      : _client = client ?? UserAgentClient(),
        _endpointOverride = endpoint;

  /// Resolve the primary endpoint: constructor override or default.
  String get _primaryEndpoint => _endpointOverride ?? defaultEndpoint;

  /// Fetch surveillance nodes from Overpass API with retry and fallback.
  /// Throws NetworkError for retryable failures, NodeLimitError for area splitting.
  Future<List<OsmNode>> fetchNodes({
    required LatLngBounds bounds,
    required List<NodeProfile> profiles,
    int? maxRetries,
  }) async {
    if (profiles.isEmpty) return [];

    final query = _buildQuery(bounds, profiles);
    // Snapshot the endpoint once so fallback decision is consistent
    final endpoint = _primaryEndpoint;
    final canFallback = endpoint == defaultEndpoint;

    final effectivePolicy = maxRetries != null
        ? ResiliencePolicy(
            maxRetries: maxRetries,
            httpTimeout: _policy.httpTimeout,
          )
        : _policy;

    return executeWithFallback<List<OsmNode>>(
      primaryUrl: endpoint,
      fallbackUrl: canFallback ? fallbackEndpoint : null,
      execute: (url) => _attemptFetch(url, query),
      classifyError: _classifyError,
      policy: effectivePolicy,
    );
  }

  /// Single POST + parse attempt (no retry logic — handled by executeWithFallback).
  Future<List<OsmNode>> _attemptFetch(String endpoint, String query) async {
    debugPrint('[OverpassService] POST $endpoint');

    try {
      final response = await _client.post(
        Uri.parse(endpoint),
        body: {'data': query},
      ).timeout(_policy.httpTimeout);

      if (response.statusCode == 200) {
        return _parseResponse(response.body);
      }

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

      // Rate limit
      if (response.statusCode == 429 ||
          errorBody.contains('rate limited') ||
          errorBody.contains('too many requests')) {
        debugPrint('[OverpassService] Rate limited by Overpass');
        throw RateLimitError('Rate limited by Overpass API');
      }

      throw NetworkError('HTTP ${response.statusCode}: $errorBody');
    } catch (e) {
      if (e is NodeLimitError || e is RateLimitError || e is NetworkError) {
        rethrow;
      }
      throw NetworkError('Network error: $e');
    }
  }

  static ErrorDisposition _classifyError(Object error) {
    if (error is NodeLimitError) return ErrorDisposition.abort;
    if (error is RateLimitError) return ErrorDisposition.fallback;
    return ErrorDisposition.retry;
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
