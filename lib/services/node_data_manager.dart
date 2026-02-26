import 'dart:async';
import 'dart:collection';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/node_profile.dart';
import '../models/osm_node.dart';
import '../app_state.dart';
import 'overpass_service.dart';
import 'node_spatial_cache.dart';
import 'network_status.dart';
import 'map_data_submodules/nodes_from_osm_api.dart';
import 'map_data_submodules/nodes_from_local.dart';
import 'offline_area_service.dart';
import 'offline_areas/offline_area_models.dart';

/// Resizable async semaphore for limiting concurrent Overpass requests.
class _AsyncSemaphore {
  int _maxConcurrent;
  int _current = 0;
  final _waiters = Queue<Completer<void>>();

  _AsyncSemaphore(int maxConcurrent) : _maxConcurrent = maxConcurrent < 1 ? 1 : maxConcurrent;

  int get maxConcurrent => _maxConcurrent;

  /// Resize the semaphore. If capacity increased, wake up queued waiters.
  void resize(int newMax) {
    _maxConcurrent = newMax < 1 ? 1 : newMax;
    // Wake exactly the number of newly available slots.
    // Can't use _current in the loop condition because woken waiters
    // haven't incremented it yet (their continuations are microtasks).
    var available = _maxConcurrent - _current;
    while (available > 0 && _waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
      available--;
    }
  }

  Future<T> run<T>(Future<T> Function() fn) async {
    while (_current >= _maxConcurrent) {
      final completer = Completer<void>();
      _waiters.add(completer);
      await completer.future;
    }
    _current++;
    try {
      return await fn();
    } finally {
      _current--;
      if (_waiters.isNotEmpty && _current < _maxConcurrent) {
        _waiters.removeFirst().complete();
      }
    }
  }
}

/// Coordinates node data fetching between cache, Overpass, and OSM API.
/// Simple interface: give me nodes for this view with proper caching and error handling.
class NodeDataManager extends ChangeNotifier {
  static final NodeDataManager _instance = NodeDataManager._();
  factory NodeDataManager() => _instance;

  NodeDataManager._({
    OverpassService? overpassService,
    NodeSpatialCache? cache,
  }) : _overpassService = overpassService ?? OverpassService(),
       _cache = cache ?? NodeSpatialCache();

  @visibleForTesting
  factory NodeDataManager.forTesting({
    OverpassService? overpassService,
    NodeSpatialCache? cache,
  }) => NodeDataManager._(overpassService: overpassService, cache: cache);

  final OverpassService _overpassService;
  final NodeSpatialCache _cache;

  // Concurrency limiter for Overpass requests
  _AsyncSemaphore? _overpassSemaphore;
  Future<_AsyncSemaphore>? _semaphoreInitFuture;

  // Generation counter for cancelling stale fetch requests.
  // Each new getNodesFor() call increments this; queued work checks before proceeding.
  int _fetchGeneration = 0;
  int? _lastLoggedStaleGeneration;

  bool _isStale(int? generation) {
    if (generation == null || generation == _fetchGeneration) return false;
    if (_lastLoggedStaleGeneration != generation) {
      _lastLoggedStaleGeneration = generation;
      debugPrint('[NodeDataManager] Fetch generation $generation is stale '
          '(current: $_fetchGeneration), cancelling remaining work');
    }
    return true;
  }

  @visibleForTesting
  void advanceFetchGeneration() => _fetchGeneration++;

  Future<_AsyncSemaphore> _getOrCreateSemaphore() {
    return _semaphoreInitFuture ??= _createSemaphore().catchError((e, st) {
      _semaphoreInitFuture = null; // Allow retry on next fetch
      Error.throwWithStackTrace(e, st);
    });
  }

  Future<_AsyncSemaphore> _createSemaphore() async {
    final slots = await _overpassService.getSlotCount();
    _overpassSemaphore = _AsyncSemaphore(slots);
    debugPrint('[NodeDataManager] Overpass semaphore: $slots slots');
    return _overpassSemaphore!;
  }

  // Track ongoing user-initiated requests for status reporting
  final Set<String> _userInitiatedRequests = <String>{};

  /// Get nodes for the given bounds and profiles.
  /// Returns cached data immediately if available, otherwise fetches from appropriate source.
  Future<List<OsmNode>> getNodesFor({
    required LatLngBounds bounds,
    required List<NodeProfile> profiles,
    UploadMode uploadMode = UploadMode.production,
    bool isUserInitiated = false,
  }) async {
    if (profiles.isEmpty) return [];

    // Handle offline mode - no loading states needed, data is instant
    if (AppState.instance.offlineMode) {
      // Clear any existing loading states since offline data is instant
      if (isUserInitiated) {
        NetworkStatus.instance.clear();
      }

      if (uploadMode == UploadMode.sandbox) {
        // Offline + Sandbox = no nodes (local cache is production data)
        debugPrint('[NodeDataManager] Offline + Sandbox mode: returning no nodes');
        return [];
      } else {
        // Offline + Production = use local offline areas (instant)
        final offlineNodes = await fetchLocalNodes(bounds: bounds, profiles: profiles);

        // Add offline nodes to cache so they integrate with the rest of the system
        if (offlineNodes.isNotEmpty) {
          _cache.addOrUpdateNodes(offlineNodes);
          // Mark this area as having coverage for submit button logic
          _cache.markAreaAsFetched(bounds, offlineNodes);
          notifyListeners();
        }

        // Show brief success for user-initiated offline loads with data
        if (isUserInitiated && offlineNodes.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            NetworkStatus.instance.setSuccess();
          });
        } else if (isUserInitiated && offlineNodes.isEmpty) {
          // Show no data briefly for offline areas with no surveillance devices
          WidgetsBinding.instance.addPostFrameCallback((_) {
            NetworkStatus.instance.setNoData();
          });
        }

        return offlineNodes;
      }
    }

    // Handle sandbox mode (always fetch from OSM API, but integrate with cache system for UI)
    if (uploadMode == UploadMode.sandbox) {
      debugPrint('[NodeDataManager] Sandbox mode: fetching from OSM API');

      // Track user-initiated requests for status reporting
      final requestKey = '${bounds.hashCode}_${profiles.map((p) => p.id).join('_')}_$uploadMode';

      if (isUserInitiated && _userInitiatedRequests.contains(requestKey)) {
        debugPrint('[NodeDataManager] Sandbox request already in progress for this area');
        return _cache.getNodesFor(bounds);
      }

      // Start status tracking for user-initiated requests
      if (isUserInitiated) {
        _userInitiatedRequests.add(requestKey);
        NetworkStatus.instance.setLoading();
        debugPrint('[NodeDataManager] Starting user-initiated sandbox request');
      } else {
        debugPrint('[NodeDataManager] Starting background sandbox request (no status reporting)');
      }

      try {
        final nodes = await fetchOsmApiNodes(
          bounds: bounds,
          profiles: profiles,
          uploadMode: uploadMode,
          maxResults: 0,
        );

        // Add nodes to cache for UI integration (even though we don't rely on cache for subsequent fetches)
        if (nodes.isNotEmpty) {
          _cache.addOrUpdateNodes(nodes);
          _cache.markAreaAsFetched(bounds, nodes);
        } else {
          // Mark area as fetched even with no nodes so UI knows we've checked this area
          _cache.markAreaAsFetched(bounds, []);
        }

        // Update UI
        notifyListeners();

        // Set success after the next frame renders, but only for user-initiated requests
        if (isUserInitiated) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            NetworkStatus.instance.setSuccess();
          });
          debugPrint('[NodeDataManager] User-initiated sandbox request completed successfully: ${nodes.length} nodes');
        }

        return nodes;

      } catch (e) {
        debugPrint('[NodeDataManager] Sandbox fetch failed: $e');

        // Only report errors for user-initiated requests
        if (isUserInitiated) {
          if (e is RateLimitError) {
            NetworkStatus.instance.setRateLimited();
          } else if (e.toString().contains('timeout')) {
            NetworkStatus.instance.setTimeout();
          } else {
            NetworkStatus.instance.setError();
          }
          debugPrint('[NodeDataManager] User-initiated sandbox request failed: $e');
        }

        // Return whatever we have in cache for this area (likely empty for sandbox)
        return _cache.getNodesFor(bounds);
      } finally {
        if (isUserInitiated) {
          _userInitiatedRequests.remove(requestKey);
        }
      }
    }

    // Production mode: check cache first
    if (_cache.hasDataFor(bounds)) {
      debugPrint('[NodeDataManager] Using cached data for bounds');
      return _cache.getNodesFor(bounds);
    }

    // Not cached - need to fetch
    final requestKey = '${bounds.hashCode}_${profiles.map((p) => p.id).join('_')}_$uploadMode';

    // Only allow one user-initiated request per area at a time
    if (isUserInitiated && _userInitiatedRequests.contains(requestKey)) {
      debugPrint('[NodeDataManager] User request already in progress for this area');
      return _cache.getNodesFor(bounds);
    }

    // Start status tracking for user-initiated requests only
    if (isUserInitiated) {
      _userInitiatedRequests.add(requestKey);
      NetworkStatus.instance.setLoading();
      debugPrint('[NodeDataManager] Starting user-initiated request');
    } else {
      debugPrint('[NodeDataManager] Starting background request (no status reporting)');
    }

    final generation = ++_fetchGeneration;
    try {
      final nodes = await fetchWithSplitting(bounds, profiles,
          isUserInitiated: isUserInitiated, generation: generation);

      // If this fetch became stale (user panned away), skip UI updates
      if (_isStale(generation)) {
        return _cache.getNodesFor(bounds);
      }

      // Update cache and notify listeners
      notifyListeners();

      // Set success after the next frame renders, but only for user-initiated requests
      if (isUserInitiated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          NetworkStatus.instance.setSuccess();
        });
        debugPrint('[NodeDataManager] User-initiated request completed successfully');
      }

      return nodes;

    } catch (e) {
      debugPrint('[NodeDataManager] Fetch failed: $e');

      // Skip error reporting for stale requests
      if (isUserInitiated && !_isStale(generation)) {
        if (e is RateLimitError) {
          NetworkStatus.instance.setRateLimited();
        } else if (e.toString().contains('timeout')) {
          NetworkStatus.instance.setTimeout();
        } else {
          NetworkStatus.instance.setError();
        }
        debugPrint('[NodeDataManager] User-initiated request failed: $e');
      }

      // Return whatever we have in cache for this area
      return _cache.getNodesFor(bounds);
    } finally {
      if (isUserInitiated) {
        _userInitiatedRequests.remove(requestKey);
      }
    }
  }

  /// Fetch nodes with automatic area splitting if needed.
  /// When [generation] is non-null, the request is cancelled if a newer
  /// generation has started (user panned/zoomed away).
  Future<List<OsmNode>> fetchWithSplitting(
    LatLngBounds bounds,
    List<NodeProfile> profiles, {
    int splitDepth = 0,
    int rateLimitRetries = 0,
    bool isUserInitiated = false,
    int? generation,
  }) async {
    const maxSplitDepth = 3; // 4^3 = 64 max sub-areas

    // Checkpoint 1: bail before entering semaphore
    if (_isStale(generation)) return [];

    try {
      // Expand bounds slightly to reduce edge effects
      final expandedBounds = _expandBounds(bounds, 1.2);

      final semaphore = await _getOrCreateSemaphore();
      // Checkpoint 2: stale request woke from queue — don't make HTTP call
      final nodes = await semaphore.run<List<OsmNode>>(
        () {
          if (_isStale(generation)) return Future.value(<OsmNode>[]);
          return _overpassService.fetchNodes(
            bounds: expandedBounds,
            profiles: profiles,
          );
        },
      );

      // Cache real data even if stale (valid for if user pans back).
      // Skip marking area if stale and got empty result (short-circuited).
      if (nodes.isNotEmpty || !_isStale(generation)) {
        _cache.markAreaAsFetched(expandedBounds, nodes);
        if (nodes.isNotEmpty) {
          notifyListeners(); // Progressive rendering: each quadrant renders immediately
        }
      }
      return nodes;

    } on NodeLimitError {
      // Hit node limit or timeout - split area if not too deep
      if (splitDepth >= maxSplitDepth) {
        debugPrint('[NodeDataManager] Max split depth reached, giving up');
        return [];
      }

      // Checkpoint 3: don't spawn 4 new sub-requests for stale fetch
      if (_isStale(generation)) return [];

      debugPrint('[NodeDataManager] Splitting area (depth: $splitDepth)');

      // Only report splitting status for user-initiated requests
      if (isUserInitiated && splitDepth == 0) {
        NetworkStatus.instance.setSplitting();
      }

      return _fetchSplitAreas(bounds, profiles, splitDepth + 1,
          isUserInitiated: isUserInitiated, generation: generation);

    } on RateLimitError {
      if (rateLimitRetries >= 2) {
        debugPrint('[NodeDataManager] Max rate limit retries reached, giving up');
        return [];
      }

      // Checkpoint 4: don't wait up to 2 minutes for a stale request
      if (_isStale(generation)) return [];

      debugPrint('[NodeDataManager] Rate limited, polling for slot (retry ${rateLimitRetries + 1}/2)');
      if (isUserInitiated) NetworkStatus.instance.setRateLimited();

      // Poll until slot available; resize semaphore with fresh slot count
      final slots = await _overpassService.waitForSlot();

      // Checkpoint 5: became stale during the wait
      if (_isStale(generation)) return [];

      _overpassSemaphore?.resize(slots);
      debugPrint('[NodeDataManager] Semaphore resized to $slots slots');

      return fetchWithSplitting(
        bounds, profiles,
        splitDepth: splitDepth,
        rateLimitRetries: rateLimitRetries + 1,
        isUserInitiated: isUserInitiated,
        generation: generation,
      );
    }
  }

  /// Fetch data by splitting area into quadrants (parallel)
  Future<List<OsmNode>> _fetchSplitAreas(
    LatLngBounds bounds,
    List<NodeProfile> profiles,
    int splitDepth, {
    bool isUserInitiated = false,
    int? generation,
  }) async {
    // Checkpoint 6: don't spawn quadrants for stale tree
    if (_isStale(generation)) return [];

    final quadrants = splitBounds(bounds);

    final results = await Future.wait(
      quadrants.map((quadrant) async {
        try {
          return await fetchWithSplitting(
            quadrant, profiles,
            splitDepth: splitDepth,
            isUserInitiated: isUserInitiated,
            generation: generation,
          );
        } catch (e) {
          debugPrint('[NodeDataManager] Quadrant fetch failed: $e');
          return <OsmNode>[];
        }
      }),
    );

    final allNodes = results.expand((nodes) => nodes).toList();
    debugPrint('[NodeDataManager] Split fetch complete: ${allNodes.length} total nodes');
    return allNodes;
  }

  /// Split bounds into 4 quadrants
  @visibleForTesting
  static List<LatLngBounds> splitBounds(LatLngBounds bounds) {
    final centerLat = (bounds.north + bounds.south) / 2;
    final centerLng = (bounds.east + bounds.west) / 2;

    return [
      // Southwest
      LatLngBounds(LatLng(bounds.south, bounds.west), LatLng(centerLat, centerLng)),
      // Southeast
      LatLngBounds(LatLng(bounds.south, centerLng), LatLng(centerLat, bounds.east)),
      // Northwest
      LatLngBounds(LatLng(centerLat, bounds.west), LatLng(bounds.north, centerLng)),
      // Northeast
      LatLngBounds(LatLng(centerLat, centerLng), LatLng(bounds.north, bounds.east)),
    ];
  }

  /// Expand bounds by given factor around center point
  LatLngBounds _expandBounds(LatLngBounds bounds, double factor) {
    final centerLat = (bounds.north + bounds.south) / 2;
    final centerLng = (bounds.east + bounds.west) / 2;

    final latSpan = (bounds.north - bounds.south) * factor / 2;
    final lngSpan = (bounds.east - bounds.west) * factor / 2;

    return LatLngBounds(
      LatLng(centerLat - latSpan, centerLng - lngSpan),
      LatLng(centerLat + latSpan, centerLng + lngSpan),
    );
  }

  /// Add or update nodes in cache (for upload queue integration)
  void addOrUpdateNodes(List<OsmNode> nodes) {
    _cache.addOrUpdateNodes(nodes);
    notifyListeners();
  }

  /// Remove node from cache (for deletions)
  void removeNodeById(int nodeId) {
    _cache.removeNodeById(nodeId);
    notifyListeners();
  }

  /// Clear cache (when profiles change significantly)
  void clearCache() {
    _cache.clear();
    notifyListeners();
  }

  /// Force refresh for current view (manual retry)
  Future<void> refreshArea({
    required LatLngBounds bounds,
    required List<NodeProfile> profiles,
    UploadMode uploadMode = UploadMode.production,
  }) async {
    // Clear any cached data for this area
    _cache.clear();

    // Re-fetch as user-initiated request
    await getNodesFor(
      bounds: bounds,
      profiles: profiles,
      uploadMode: uploadMode,
      isUserInitiated: true,
    );
  }

  /// NodeCache compatibility methods
  OsmNode? getNodeById(int nodeId) => _cache.getNodeById(nodeId);
  void removePendingEditMarker(int nodeId) => _cache.removePendingEditMarker(nodeId);
  void removePendingDeletionMarker(int nodeId) => _cache.removePendingDeletionMarker(nodeId);
  void removeTempNodeById(int tempNodeId) => _cache.removeTempNodeById(tempNodeId);
  List<OsmNode> findNodesWithinDistance(LatLng coord, double distanceMeters, {int? excludeNodeId}) =>
      _cache.findNodesWithinDistance(coord, distanceMeters, excludeNodeId: excludeNodeId);

  /// Check if we have good cache coverage for the given area
  bool hasGoodCoverageFor(LatLngBounds bounds) {
    return _cache.hasDataFor(bounds);
  }

  /// Load all offline nodes into cache (call at app startup)
  Future<void> preloadOfflineNodes() async {
    try {
      final offlineAreaService = OfflineAreaService();

      for (final area in offlineAreaService.offlineAreas) {
        if (area.status != OfflineAreaStatus.complete) continue;

        // Load nodes from this offline area
        final nodes = await fetchLocalNodes(
          bounds: area.bounds,
          profiles: [], // Empty profiles = load all nodes
        );

        if (nodes.isNotEmpty) {
          _cache.addOrUpdateNodes(nodes);
          // Mark the offline area as having coverage so submit buttons work
          _cache.markAreaAsFetched(area.bounds, nodes);
          debugPrint('[NodeDataManager] Preloaded ${nodes.length} offline nodes from area ${area.name}');
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[NodeDataManager] Error preloading offline nodes: $e');
    }
  }

  /// Get cache statistics
  String get cacheStats => _cache.stats.toString();
}
