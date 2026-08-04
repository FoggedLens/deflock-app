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

  /// Build Overpass QL query for given bounds and profiles.
  ///
  /// Profiles are deduplicated first: if one profile's non-empty tags are a
  /// subset of another's (with identical values), the broader profile's query
  /// clause already returns every node the narrower one would, so the
  /// narrower clause is redundant and can be dropped. This directly reduces
  /// query size/complexity without changing the result set — client-side
  /// filtering (matching returned nodes against the full profile list) still
  /// happens independently, so nothing is lost.
  String _buildQuery(LatLngBounds bounds, List<NodeProfile> profiles) {
    final profilesToQuery = _deduplicateProfilesForQuery(profiles);

    if (profilesToQuery.length < profiles.length) {
      debugPrint(
          '[OverpassService] Deduplicated ${profiles.length} profiles to ${profilesToQuery.length} for query efficiency');
    }

    // Per-profile tag filter strings (e.g. ["man_made"="surveillance"]["surveillance:type"="ALPR"]),
    // excluding empty tag values. Reused twice below: once to select our nodes
    // in the bbox, and again to re-select just our nodes out of the pool of
    // way/relation-connected nodes (which may include unrelated node types).
    final tagFilterStrings = profilesToQuery.map((profile) {
      return profile.tags.entries
          .where((entry) => entry.value.trim().isNotEmpty)
          .map((entry) => '["${entry.key}"="${entry.value}"]')
          .join();
    }).toList();

    final bboxStr = '${bounds.southWest.latitude},${bounds.southWest.longitude},'
        '${bounds.northEast.latitude},${bounds.northEast.longitude}';

    final allNodesClauses =
        tagFilterStrings.map((filters) => 'node$filters($bboxStr);').join('\n  ');
    final resNodesClauses =
        tagFilterStrings.map((filters) => 'node.resNodes$filters;').join('\n  ');

    // Query strategy:
    // 1. Find all matching nodes in bbox -> .allNodes, output them with tags ("out body").
    // 2. Find any way/relation that references one of .allNodes ("bn." = "by node"),
    //    then pull the node IDs those ways/relations reference -> .wayNodes/.relNodes.
    //    (`node(w)`/`node(r)` on a way/relation set returns only node IDs, not
    //    full tags/coords, keeping the query/response cheap.)
    // 3. Re-filter that combined node pool down to just our own matching
    //    surveillance nodes (.resNodes may contain unrelated node types too).
    // 4. `convert restriction ::id = id();` emits each of those node IDs as a
    //    lightweight synthetic `{"type":"restriction","id":<nodeId>}` element —
    //    a flat, unambiguous list of which node IDs are "constrained" (part of
    //    some way/relation), without needing the full way/relation node lists.
    return '''
[out:json][timeout:${kOverpassQueryTimeout.inSeconds}];
(
  $allNodesClauses
)->.allNodes;
.allNodes out body;
way(bn.allNodes); node(w)->.wayNodes;
relation(bn.allNodes); node(r)->.relNodes;
(.wayNodes;.relNodes;)->.resNodes;
(
  $resNodesClauses
);
convert restriction ::id = id();
out;
''';
  }


  /// Deduplicate profiles for Overpass queries by removing profiles that are
  /// subsumed by others. A profile A subsumes profile B if all of A's
  /// non-empty tags exist in B with identical values — meaning every node
  /// matching B's filter also matches A's filter, so B's clause is redundant.
  List<NodeProfile> _deduplicateProfilesForQuery(List<NodeProfile> profiles) {
    if (profiles.length <= 1) return profiles;

    final result = <NodeProfile>[];

    for (final candidate in profiles) {
      // Skip profiles that only have empty tags - they would match
      // everything and shouldn't be treated as subsuming or subsumable.
      final candidateNonEmptyTags = candidate.tags.entries
          .where((entry) => entry.value.trim().isNotEmpty)
          .toList();

      if (candidateNonEmptyTags.isEmpty) continue;

      // Check if any existing profile in our result subsumes this candidate
      bool isSubsumed = false;
      for (final existing in result) {
        if (_profileSubsumes(existing, candidate)) {
          isSubsumed = true;
          break;
        }
      }

      if (!isSubsumed) {
        // This candidate is not subsumed, so add it. But first, remove any
        // existing profiles that this candidate subsumes (candidate is
        // broader, so those clauses are now redundant).
        result.removeWhere((existing) => _profileSubsumes(candidate, existing));
        result.add(candidate);
      }
    }

    // Safety check: if dedup removed everything (e.g. all-empty-tag
    // profiles), fall back to the original list rather than sending an
    // empty query.
    return result.isNotEmpty ? result : profiles;
  }

  /// Check if [broaderProfile] subsumes [specificProfile]: true if all
  /// non-empty tags in [broaderProfile] exist in [specificProfile] with
  /// identical values.
  bool _profileSubsumes(NodeProfile broaderProfile, NodeProfile specificProfile) {
    final broaderTags = Map.fromEntries(
      broaderProfile.tags.entries.where((entry) => entry.value.trim().isNotEmpty),
    );
    final specificTags = Map.fromEntries(
      specificProfile.tags.entries.where((entry) => entry.value.trim().isNotEmpty),
    );

    // If broader has no non-empty tags, it doesn't subsume anything (it
    // would match everything, which isn't a meaningful "broader filter").
    if (broaderTags.isEmpty) return false;

    // If broader has more non-empty tags than specific, it can't subsume it.
    if (broaderTags.length > specificTags.length) return false;

    for (final entry in broaderTags.entries) {
      if (specificTags[entry.key] != entry.value) return false;
    }

    return true;
  }


  /// Parse Overpass JSON response into OsmNode objects.
  ///
  /// The query (see [_buildQuery]) produces two kinds of elements:
  /// - `type: "node"` — our matched surveillance nodes, with full tags/coords
  ///   (from `.allNodes out body;`).
  /// - `type: "restriction"` — synthetic elements (from
  ///   `convert restriction ::id = id();`) whose `id` is the OSM node ID of
  ///   one of our nodes that Overpass determined is referenced by some way
  ///   or relation. These carry no lat/lon/tags — just the id — and exist
  ///   purely to tell us which node IDs are "constrained".
  List<OsmNode> _parseResponse(String responseBody) {
    final data = jsonDecode(responseBody) as Map<String, dynamic>;
    final elements = data['elements'] as List<dynamic>;

    final nodeElements = <Map<String, dynamic>>[];
    final constrainedNodeIds = <int>{};

    // First pass: collect surveillance nodes and constrained-node markers.
    for (final element in elements.whereType<Map<String, dynamic>>()) {
      final type = element['type'] as String?;

      if (type == 'node') {
        nodeElements.add(element);
      } else if (type == 'restriction') {
        final rawId = element['id'];
        final nodeId = rawId is int ? rawId : int.tryParse(rawId.toString());
        if (nodeId != null) constrainedNodeIds.add(nodeId);
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
