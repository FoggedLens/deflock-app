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
  /// Optional override endpoint. When null, uses [defaultEndpoint].
  final String? _endpointOverride;

  OverpassService({http.Client? client, String? endpoint})
      : _client = client ?? UserAgentClient(),
        _endpointOverride = endpoint;

  /// Resolve the primary endpoint: constructor override or default.
  String get _primaryEndpoint => _endpointOverride ?? defaultEndpoint;

  /// Fetch surveillance nodes from Overpass API with retry and fallback.
  ///
  /// Throws:
  /// - [NodeLimitError] when the query would exceed Overpass's hard 50k node
  ///   limit. This is the *only* case where the caller should split the
  ///   query area into smaller regions, since it's a deterministic function
  ///   of how much data lives in the requested bounds.
  /// - [RateLimitError] when rate limited (HTTP 429 or equivalent). Callers
  ///   should back off, not split/retry — splitting would only amplify load
  ///   on a server that just told us to slow down.
  /// - [NetworkError] for timeouts and other retryable HTTP/network failures.
  ///   Timeouts are usually a sign of server load or an expensive query, not
  ///   "too much area" — retrying with a hail of smaller sub-requests makes
  ///   the problem worse, so timeouts are treated like any other transient
  ///   network failure (handled by the existing retry/backoff/fallback logic).
  Future<List<OsmNode>> fetchNodes({
    required LatLngBounds bounds,
    required List<NodeProfile> profiles,
    ResiliencePolicy? policy,
  }) async {
    if (profiles.isEmpty) return [];

    final query = _buildQuery(bounds, profiles);
    final endpoint = _primaryEndpoint;
    final canFallback = _endpointOverride == null;
    final effectivePolicy = policy ?? _policy;

    return executeWithFallback<List<OsmNode>>(
      primaryUrl: endpoint,
      fallbackUrl: canFallback ? fallbackEndpoint : null,
      execute: (url) => _attemptFetch(url, query, effectivePolicy),
      classifyError: _classifyError,
      policy: effectivePolicy,
    );
  }

  /// Single POST + parse attempt (no retry logic — handled by executeWithFallback).
  Future<List<OsmNode>> _attemptFetch(String endpoint, String query, ResiliencePolicy policy) async {
    debugPrint('[OverpassService] POST $endpoint');

    try {
      final response = await _client.post(
        Uri.parse(endpoint),
        body: {'data': query},
      ).timeout(policy.httpTimeout);

      if (response.statusCode == 200) {
        return _parseResponse(response.body);
      }

      final errorBody = response.body;

      // Node limit error - a deterministic result-set size limit. This is
      // the one case where splitting the query area into smaller regions is
      // the correct fix, since it directly reduces nodes-per-request.
      if (response.statusCode == 400 &&
          (errorBody.contains('too many nodes') && errorBody.contains('50000'))) {
        debugPrint('[OverpassService] Node limit exceeded (50k), area should be split');
        throw NodeLimitError('Query exceeded 50k node limit');
      }

      // Rate limit - back off, don't split or hammer the server with more requests.
      if (response.statusCode == 429 ||
          errorBody.contains('rate limited') ||
          errorBody.contains('too many requests')) {
        debugPrint('[OverpassService] Rate limited by Overpass');
        throw RateLimitError('Rate limited by Overpass API');
      }

      // Timeout / runtime limit exceeded - treat as a plain retryable network
      // error. This is usually server load or query cost, not "area too
      // big" — splitting into up to 64 sub-requests would only make load
      // on the server worse.
      if (errorBody.contains('timeout') ||
          errorBody.contains('runtime limit exceeded') ||
          errorBody.contains('Query timed out')) {
        debugPrint('[OverpassService] Query timed out');
        throw NetworkError('Query timed out');
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
<;
out ids;
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

/// Error thrown when a query would exceed Overpass's 50k node limit.
/// The caller should split the query area into smaller regions to resolve this
/// — it's a deterministic function of how much data lives within the bounds.
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

/// Error thrown for network/HTTP issues (including timeouts) - retryable
class NetworkError extends Error {
  final String message;
  NetworkError(this.message);
  @override
  String toString() => 'NetworkError: $message';
}
