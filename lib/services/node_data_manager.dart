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

/// Resizable async semaphore with priority support.
///
/// User-initiated (priority) requests jump to the front of the queue so they
/// are never blocked behind prefetch or background refresh work. Background
/// items stay queued and bail on staleness when they eventually wake.
class _AsyncSemaphore {
  int _maxConcurrent;
  int _current = 0;
  final _waiters = Queue<Completer<void>>();
  DateTime? _cooldownUntil;

  _AsyncSemaphore(int maxConcurrent) : _maxConcurrent = maxConcurrent < 1 ? 1 : maxConcurrent;

  int get maxConcurrent => _maxConcurrent;
  int get activeCount => _current;
  int get queueLength => _waiters.length;
  bool get isCoolingDown =>
      _cooldownUntil != null && DateTime.now().isBefore(_cooldownUntil!);

  int get cooldownRemainingSeconds => _cooldownUntil == null
      ? 0
      : _cooldownUntil!.difference(DateTime.now()).inSeconds.clamp(0, 30);

  /// Pause all requests for [duration]. Used when Overpass reports a rate
  /// limit — no point sending requests we know will be rejected.
  /// Also temporarily reduces to 1 slot to avoid burning both slots
  /// immediately after cooldown expires.
  void cooldown(Duration duration) {
    final until = DateTime.now().add(duration);
    // Only extend, never shorten an active cooldown
    if (_cooldownUntil == null || until.isAfter(_cooldownUntil!)) {
      _cooldownUntil = until;
      // Reduce to 1 slot coming out of rate limit — prevents two concurrent
      // 7s queries from consuming both slots and triggering another rate limit.
      // Restored to full capacity after a successful request.
      _maxConcurrent = 1;
      debugPrint('[Semaphore] Cooldown set for ${duration.inSeconds}s, reduced to 1 slot');
    }
  }

  /// Restore full slot capacity after a successful request post-cooldown.
  void restoreCapacity(int slots) {
    if (_maxConcurrent < slots) {
      _maxConcurrent = slots;
      debugPrint('[Semaphore] Restored to $slots slots');
      // Wake a queued waiter if one is waiting for the new slot
      if (_waiters.isNotEmpty && _current < _maxConcurrent) {
        _waiters.removeFirst().complete();
      }
    }
  }

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

  Future<T> run<T>(Future<T> Function() fn, {bool priority = false}) async {
    // Wait for cooldown before competing for a slot.
    // Re-check after waking — another caller may have already cleared it.
    await _waitForCooldown();

    while (_current >= _maxConcurrent) {
      final completer = Completer<void>();
      // Priority (user-initiated) requests go to the front so the most recent
      // user pan is served first — it's the viewport they're actually looking at.
      if (priority) {
        _waiters.addFirst(completer);
      } else {
        _waiters.addLast(completer);
      }
      await completer.future;
      // Re-check cooldown after waking from slot wait — cooldown() may have
      // been called while we were queued.
      await _waitForCooldown();
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

  /// Block until cooldown expires. Re-checks in a loop because cooldown()
  /// may extend the deadline while we're waiting.
  Future<void> _waitForCooldown() async {
    while (_cooldownUntil != null) {
      final remaining = _cooldownUntil!.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        _cooldownUntil = null;
        break;
      }
      debugPrint('[Semaphore] Waiting ${remaining.inSeconds}s for cooldown');
      await Future.delayed(remaining);
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

  // Limit concurrent Overpass requests to the known slot count (2 per IP).
  _AsyncSemaphore? _overpassSemaphore;

  _AsyncSemaphore get _semaphore =>
      _overpassSemaphore ??= _AsyncSemaphore(OverpassService.defaultSlotCount);

  // Throttle progressive notifications to avoid repeated expensive marker rebuilds
  Timer? _progressiveNotifyTimer;

  // Generation counter for cancelling stale fetch requests.
  // Incremented only when the user pans to an area NOT covered by the current
  // in-flight request's expanded bounds. This prevents rapid cancel/re-fetch
  // cycles when the user pans slightly within the 1.2x fetch area.
  int _fetchGeneration = 0;
  int? _lastLoggedStaleGeneration;

  // Track the expanded bounds of the current in-flight user-initiated fetch.
  // When a new request comes in, if the in-flight bounds already cover the
  // new viewport, we skip cancelling and let it finish — its 1.2x expansion
  // likely covers the new viewport anyway.
  LatLngBounds? _inFlightBounds;

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

  /// Throttled notification for progressive rendering.
  /// Batches rapid quadrant completions into one rebuild (~200ms window).
  void _notifyProgressive() {
    _progressiveNotifyTimer?.cancel();
    _progressiveNotifyTimer = Timer(const Duration(milliseconds: 200), () {
      notifyListeners();
    });
  }

  // Track ongoing user-initiated requests for status reporting
  final Set<String> _userInitiatedRequests = <String>{};

  // Track in-flight background refreshes to avoid duplicates
  final Set<String> _backgroundRefreshKeys = <String>{};

  // Separate generation for prefetch loops so a new cache-hit cancels
  // the previous prefetch without requiring a fetch-generation bump.
  int _prefetchGeneration = 0;

  // Reconciliation: auto-retry the current viewport after a failed fetch.
  LatLngBounds? _pendingViewport;
  List<NodeProfile>? _pendingProfiles;
  Timer? _reconciliationTimer;

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
            NetworkStatus.instance.setRateLimited(waitSeconds: e.waitSeconds);
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
      final staleBounds = _cache.staleAreaFor(bounds);
      if (staleBounds != null) {
        _backgroundRefresh(staleBounds, profiles);
      }
      // Only prefetch at higher zoom levels where areas are small enough
      // to be worth speculative fetching. At low zoom (~10), each cell is
      // ~1° × 0.67° — prefetching 48 of those wastes rate limit budget.
      final latSpan = bounds.north - bounds.south;
      if (latSpan < 0.2) {
        _prefetchSurroundings(bounds, profiles);
      }
      final cachedNodes = _cache.getNodesFor(bounds);
      debugPrint('[NodeDataManager] Cache hit: ${cachedNodes.length} nodes, '
          'stale=${staleBounds != null}');
      return cachedNodes;
    }

    // Not cached - need to fetch
    final requestKey = '${bounds.hashCode}_${profiles.map((p) => p.id).join('_')}_$uploadMode';

    // If the semaphore is cooling down (rate limited), don't queue more
    // requests — they'll just wait and go stale. Reconciliation will
    // retry with the correct viewport when the cooldown expires.
    if (_semaphore.isCoolingDown) {
      debugPrint('[NodeDataManager] Semaphore cooling down, deferring to reconciliation');
      if (isUserInitiated) {
        _pendingViewport = bounds;
        _pendingProfiles = profiles;
        NetworkStatus.instance.setRateLimited(waitSeconds: _semaphore.cooldownRemainingSeconds);
      }
      return _cache.getNodesFor(bounds);
    }

    // Only allow one user-initiated request per area at a time
    if (isUserInitiated && _userInitiatedRequests.contains(requestKey)) {
      debugPrint('[NodeDataManager] User request already in progress for this area');
      return _cache.getNodesFor(bounds);
    }

    // If there's an in-flight request whose 1.2x expanded bounds already
    // cover this viewport, don't cancel it — let it finish. The user panned
    // slightly but the existing fetch will cover the new view.
    if (_inFlightBounds != null &&
        _inFlightBounds!.containsBounds(bounds)) {
      debugPrint('[NodeDataManager] In-flight request covers viewport, skipping new fetch '
          '(gen $_fetchGeneration)');
      if (isUserInitiated) {
        NetworkStatus.instance.setLoading();
      }
      return _cache.getNodesFor(bounds);
    }

    // Start status tracking for user-initiated requests only
    if (isUserInitiated) {
      _userInitiatedRequests.add(requestKey);
      NetworkStatus.instance.setLoading();
      debugPrint('[NodeDataManager] Starting user-initiated request '
          '(semaphore: ${_semaphore.activeCount}/${_semaphore.maxConcurrent}, '
          'queued: ${_semaphore.queueLength})');
    } else {
      debugPrint('[NodeDataManager] Starting background request (no status reporting)');
    }

    _reconciliationTimer?.cancel();  // New request supersedes pending retry
    _pendingViewport = null;
    _pendingProfiles = null;
    final stopwatch = Stopwatch()..start();
    final generation = ++_fetchGeneration;
    // Use a larger expansion for in-flight tracking at low zoom so that
    // small pans during the multi-second Overpass response don't cancel
    // the request. At zoom 10 (latSpan ~1°), 1.5x adds ~0.25° per side;
    // at zoom 14 (latSpan ~0.06°), 1.2x is sufficient.
    final latSpan = bounds.north - bounds.south;
    final inFlightExpansion = latSpan > 0.5 ? 1.5 : 1.2;
    _inFlightBounds = _expandBounds(bounds, inFlightExpansion);
    try {
      final nodes = await fetchWithSplitting(bounds, profiles,
          isUserInitiated: isUserInitiated, generation: generation);

      // If this fetch became stale (user panned away), skip UI updates
      // but clear rate-limited status since a new request will take over
      if (_isStale(generation)) {
        if (NetworkStatus.instance.status == NetworkRequestStatus.rateLimited) {
          NetworkStatus.instance.clear();
        }
        return _cache.getNodesFor(bounds);
      }

      // If the fetch returned empty (e.g. rate limited), fall back to
      // whatever the cache has from prior fetches of overlapping areas.
      final result = nodes.isEmpty ? _cache.getNodesFor(bounds) : nodes;

      // Progressive notifications already covered UI updates per quadrant;
      // flush any pending throttled notification so the final state renders.
      _progressiveNotifyTimer?.cancel();
      _progressiveNotifyTimer = null;
      notifyListeners();

      // Success — clear any pending reconciliation
      _reconciliationTimer?.cancel();
      _pendingViewport = null;
      _pendingProfiles = null;

      // Set success after the next frame renders, but only for user-initiated requests
      if (isUserInitiated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          NetworkStatus.instance.setSuccess();
        });
        debugPrint('[NodeDataManager] User-initiated request completed: ${result.length} nodes (${stopwatch.elapsedMilliseconds}ms)');
      }

      if (latSpan < 0.2) {
        _prefetchSurroundings(bounds, profiles);
      }
      return result;

    } catch (e) {
      debugPrint('[NodeDataManager] Fetch failed: $e');

      // Skip error reporting for stale requests
      if (isUserInitiated && !_isStale(generation)) {
        if (e is RateLimitError) {
          NetworkStatus.instance.setRateLimited(waitSeconds: e.waitSeconds);
        } else if (e.toString().contains('timeout')) {
          NetworkStatus.instance.setTimeout();
        } else {
          NetworkStatus.instance.setError();
        }
        debugPrint('[NodeDataManager] User-initiated request failed (${stopwatch.elapsedMilliseconds}ms): $e');

        // Schedule auto-retry for the current viewport, using the actual
        // wait time from Overpass /api/status when available.
        _pendingViewport = bounds;
        _pendingProfiles = profiles;
        final retryDelay = e is RateLimitError ? e.waitSeconds : 5;
        _scheduleReconciliation(delaySeconds: retryDelay);
      }

      // Return whatever we have in cache for this area
      return _cache.getNodesFor(bounds);
    } finally {
      // Clear in-flight tracking when this generation's fetch finishes.
      // Only clear if we're still the current in-flight request (not staled).
      if (!_isStale(generation)) {
        _inFlightBounds = null;
      }
      if (isUserInitiated) {
        _userInitiatedRequests.remove(requestKey);
      }
    }
  }

  /// Fetch nodes with automatic area splitting on NodeLimitError.
  ///
  /// RateLimitError is rethrown to the caller — reconciliation handles retry.
  ///
  /// Cancellation via [generation]:
  /// - null: request is never cancelled (used by offline area downloads)
  /// - non-null: cancelled at checkpoints when _fetchGeneration advances
  ///
  /// In-flight HTTP calls can't be cancelled (Dart limitation). When a
  /// response arrives for a stale generation, the data is still cached
  /// (nodes.isNotEmpty guard) — the work is done, don't throw it away.
  Future<List<OsmNode>> fetchWithSplitting(
    LatLngBounds bounds,
    List<NodeProfile> profiles, {
    int splitDepth = 0,
    bool isUserInitiated = false,
    int? generation,
  }) async {
    const maxSplitDepth = 3; // 4^3 = 64 max sub-areas

    // Checkpoint 1: bail before entering semaphore queue
    if (_isStale(generation)) return [];

    try {
      // Expand bounds slightly to reduce edge effects
      final expandedBounds = _expandBounds(bounds, 1.2);

      // User-initiated requests jump to the front of the semaphore queue
      // so they're never blocked behind prefetch/background work.
      // Checkpoint 2: request woke from semaphore queue — check before HTTP call
      final semaphoreWait = Stopwatch()..start();
      final nodes = await _semaphore.run<List<OsmNode>>(
        () async {
          final waitMs = semaphoreWait.elapsedMilliseconds;
          if (waitMs > 100) {
            debugPrint('[NodeDataManager] Semaphore wait: ${waitMs}ms');
          }
          if (_isStale(generation)) return <OsmNode>[];
          return _overpassService.fetchNodes(
            bounds: expandedBounds,
            profiles: profiles,
          );
        },
        priority: isUserInitiated,
      );

      // Successful fetch — restore full semaphore capacity if it was
      // reduced during rate-limit cooldown.
      _semaphore.restoreCapacity(OverpassService.defaultSlotCount);

      // Always cache real data, even if stale — valid if user pans back.
      // Only skip caching when stale AND empty (the checkpoint-2 short-circuit).
      if (nodes.isNotEmpty || !_isStale(generation)) {
        _cache.markAreaAsFetched(expandedBounds, nodes);
        if (nodes.isNotEmpty) {
          _notifyProgressive(); // Throttled: batches rapid quadrant completions
        }
      }
      return nodes;

    } on NodeLimitError {
      if (splitDepth >= maxSplitDepth) {
        debugPrint('[NodeDataManager] Max split depth reached, giving up');
        return [];
      }

      // Checkpoint 3: don't spawn 4 new sub-requests for stale fetch
      if (_isStale(generation)) return [];

      debugPrint('[NodeDataManager] Splitting area (depth: $splitDepth)');

      if (isUserInitiated && splitDepth == 0) {
        NetworkStatus.instance.setSplitting();
      }

      // Each sub-request re-enters the semaphore independently (sequential,
      // not parallel) so it competes fairly with other callers.
      return _fetchSplitAreas(bounds, profiles, splitDepth + 1,
          isUserInitiated: isUserInitiated, generation: generation);

    } on RateLimitError catch (e) {
      // Pause the semaphore so queued requests don't each independently
      // hit the pre-flight and fail. When cooldown expires, requests flow.
      _semaphore.cooldown(Duration(seconds: e.waitSeconds));
      // Kill any in-progress prefetch so those queued cells don't wake up
      // after cooldown and consume slots before user-initiated requests.
      _prefetchGeneration++;
      debugPrint('[NodeDataManager] Rate limited (${e.waitSeconds}s), deferring to reconciliation');
      rethrow;
    }
  }

  /// Fetch data by splitting area into quadrants (sequential).
  /// Sequential avoids flooding Overpass — parallel requests just queue
  /// behind the semaphore and trigger 429s.
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
    final allNodes = <OsmNode>[];

    for (final quadrant in quadrants) {
      if (_isStale(generation)) break;
      try {
        final nodes = await fetchWithSplitting(
          quadrant, profiles,
          splitDepth: splitDepth,
          isUserInitiated: isUserInitiated,
          generation: generation,
        );
        allNodes.addAll(nodes);
      } on RateLimitError {
        // If one quadrant is rate-limited, the rest will be too.
        // Rethrow so reconciliation handles retry with the right delay.
        rethrow;
      } catch (e) {
        debugPrint('[NodeDataManager] Quadrant fetch failed: $e');
      }
    }

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
    // Invalidate only the areas covering these bounds so they're re-fetched
    _cache.invalidateArea(bounds);

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

  /// Fire-and-forget background refresh for stale cached areas.
  /// Snapshots _fetchGeneration so user pans cancel queued work, but in-flight
  /// HTTP responses are still cached (see markAreaAsFetched nodesNotEmpty guard).
  void _backgroundRefresh(LatLngBounds bounds, List<NodeProfile> profiles) {
    final key = '${bounds.south},${bounds.west},${bounds.north},${bounds.east}';
    if (_backgroundRefreshKeys.contains(key)) return;

    _backgroundRefreshKeys.add(key);

    final effectiveProfiles = profiles.isNotEmpty
        ? profiles
        : AppState.instance.enabledProfiles;

    final generation = _fetchGeneration;
    debugPrint('[NodeDataManager] Starting background refresh (gen $generation)');

    () async {
      try {
        await fetchWithSplitting(bounds, effectiveProfiles,
            isUserInitiated: false, generation: generation);
        _progressiveNotifyTimer?.cancel();
        _progressiveNotifyTimer = null;
        notifyListeners();
      } catch (e) {
        debugPrint('[NodeDataManager] Background refresh failed (silently): $e');
      } finally {
        _backgroundRefreshKeys.remove(key);
      }
    }();
  }

  /// Start prefetching surrounding areas in expanding rings around the viewport.
  ///
  /// Cancellation has two layers:
  /// - _prefetchGeneration: bumped on each call, stops the loop from queuing
  ///   new cells when the user pans to a different cached area.
  /// - _fetchGeneration (via fetchWithSplitting): bumped when the user pans to
  ///   an uncached area, cancels queued semaphore work and prevents new splits
  ///   or rate-limit retries. In-flight HTTP responses are still cached thanks
  ///   to the `nodes.isNotEmpty` guard in fetchWithSplitting.
  void _prefetchSurroundings(LatLngBounds viewport, List<NodeProfile> profiles) {
    // Bump prefetch generation to stop the previous loop from queuing new cells.
    final prefetchGen = ++_prefetchGeneration;
    // Snapshot fetch generation so user pans to uncached areas cancel queued work.
    final fetchGen = _fetchGeneration;
    debugPrint('[NodeDataManager] Starting prefetch (prefetchGen $prefetchGen, fetchGen $fetchGen)');

    () async {
      // After rate-limit recovery, delay prefetch so user-initiated requests
      // get slot priority. Skip delay when semaphore is at full capacity.
      if (_semaphore.maxConcurrent < OverpassService.defaultSlotCount) {
        await Future.delayed(const Duration(seconds: 3));
        if (prefetchGen != _prefetchGeneration || _isStale(fetchGen)) return;
      }

      final effectiveProfiles = profiles.isNotEmpty
          ? profiles
          : AppState.instance.enabledProfiles;
      if (effectiveProfiles.isEmpty) return;

      final cells = _generateRingCells(viewport, 3); // 3 rings max
      final uncachedCount = cells.where((c) => !_cache.hasDataFor(c)).length;
      debugPrint('[NodeDataManager] Prefetch: ${cells.length} cells, $uncachedCount uncached');
      for (final cell in cells) {
        // Stop queuing new cells if a newer prefetch started or user panned
        if (prefetchGen != _prefetchGeneration || _isStale(fetchGen)) return;

        // Skip already-cached cells
        if (_cache.hasDataFor(cell)) continue;

        try {
          await fetchWithSplitting(cell, effectiveProfiles,
              isUserInitiated: false, generation: fetchGen);
          _progressiveNotifyTimer?.cancel();
          _progressiveNotifyTimer = null;
          notifyListeners();
        } catch (e) {
          debugPrint('[NodeDataManager] Prefetch cell failed (silently): $e');
        }

        // Delay between requests to stay well under rate limit
        if (prefetchGen != _prefetchGeneration || _isStale(fetchGen)) return;
        await Future.delayed(const Duration(seconds: 5));
      }
    }();
  }

  /// Generate ring cells around the viewport in expanding rings.
  /// Ring 1 = 8 cells adjacent, Ring 2 = 16 cells, Ring 3 = 24 cells, etc.
  @visibleForTesting
  static List<LatLngBounds> generateRingCells(LatLngBounds viewport, int maxRings) {
    return _generateRingCells(viewport, maxRings);
  }

  static List<LatLngBounds> _generateRingCells(LatLngBounds viewport, int maxRings) {
    final latSpan = viewport.north - viewport.south;
    final lngSpan = viewport.east - viewport.west;
    final cells = <LatLngBounds>[];

    for (int ring = 1; ring <= maxRings; ring++) {
      // Walk the perimeter of the ring
      for (int dx = -ring; dx <= ring; dx++) {
        for (int dy = -ring; dy <= ring; dy++) {
          // Only include cells on the perimeter of this ring
          if (dx.abs() != ring && dy.abs() != ring) continue;

          final south = viewport.south + dy * latSpan;
          final west = viewport.west + dx * lngSpan;
          cells.add(LatLngBounds(
            LatLng(south, west),
            LatLng(south + latSpan, west + lngSpan),
          ));
        }
      }
    }

    return cells;
  }

  /// Schedule a reconciliation retry for a failed viewport fetch.
  /// [delaySeconds] defaults to 5 but is set from the Overpass /api/status
  /// wait time when available, so we retry right when a slot opens.
  void _scheduleReconciliation({int delaySeconds = 5}) {
    _reconciliationTimer?.cancel();
    debugPrint('[NodeDataManager] Reconciliation scheduled in ${delaySeconds}s');
    // Schedule after cooldown expires — if reconciliation fires while the
    // semaphore is still cooling down, it'll hit the guard and get dropped.
    final cooldownRemaining = _semaphore.cooldownRemainingSeconds;
    final effectiveDelay = delaySeconds < cooldownRemaining
        ? cooldownRemaining + 1  // Wait for cooldown + 1s buffer
        : delaySeconds;
    if (effectiveDelay != delaySeconds) {
      debugPrint('[NodeDataManager] Reconciliation adjusted to ${effectiveDelay}s (cooldown: ${cooldownRemaining}s)');
    }
    _reconciliationTimer = Timer(Duration(seconds: effectiveDelay), () {
      final viewport = _pendingViewport;
      final profiles = _pendingProfiles;
      _pendingViewport = null;
      _pendingProfiles = null;
      if (viewport == null || profiles == null) return;
      if (_cache.hasFreshDataFor(viewport)) return; // Already filled with fresh data

      debugPrint('[NodeDataManager] Reconciliation: retrying viewport fetch');
      getNodesFor(bounds: viewport, profiles: profiles, isUserInitiated: true);
    });
  }

  @override
  void dispose() {
    _reconciliationTimer?.cancel();
    _progressiveNotifyTimer?.cancel();
    super.dispose();
  }

  /// Get fetched areas with timestamps (for coverage overlay).
  List<CachedArea> get fetchedAreas => _cache.fetchedAreas;

  /// Get cache statistics
  String get cacheStats => _cache.stats.toString();
}
