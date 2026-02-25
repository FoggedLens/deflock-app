import 'dart:async';

import 'package:flutter/foundation.dart';

/// Identifies the type of external service being accessed.
/// Used by [ServicePolicyResolver] to determine the correct compliance policy.
enum ServiceType {
  // OSMF official services
  osmEditingApi, // api.openstreetmap.org — editing & data queries
  osmTileServer, // tile.openstreetmap.org — raster tiles
  nominatim, // nominatim.openstreetmap.org — geocoding
  overpass, // overpass-api.de — read-only data queries
  tagInfo, // taginfo.openstreetmap.org — tag metadata

  // Third-party tile services
  bingTiles, // *.tiles.virtualearth.net
  mapboxTiles, // api.mapbox.com

  // Everything else
  custom, // user's own infrastructure / unknown
}

/// Defines the compliance rules for a specific service.
///
/// Each policy captures the rate limits, caching requirements, offline
/// permissions, and attribution obligations mandated by the service operator.
/// When the app talks to official OSMF infrastructure the strict policies
/// apply; when the user configures self-hosted endpoints, [ServicePolicy.custom]
/// provides permissive defaults.
class ServicePolicy {
  /// Max concurrent HTTP connections to this service.
  /// A value of 0 means "managed elsewhere" (e.g., by flutter_map or PR #114).
  final int maxConcurrentRequests;

  /// Minimum interval between consecutive requests. Null means no rate limit.
  final Duration? minRequestInterval;

  /// Whether this endpoint permits offline/bulk downloading of tiles.
  final bool allowsOfflineDownload;

  /// Whether the client must cache responses (e.g., Nominatim policy).
  final bool requiresClientCaching;

  /// Minimum cache TTL to enforce regardless of server headers.
  /// Null means "use server-provided max-age as-is".
  final Duration? minCacheTtl;

  /// License/attribution URL to display in the attribution dialog.
  /// Null means no special attribution link is needed.
  final String? attributionUrl;

  const ServicePolicy({
    this.maxConcurrentRequests = 8,
    this.minRequestInterval,
    this.allowsOfflineDownload = true,
    this.requiresClientCaching = false,
    this.minCacheTtl,
    this.attributionUrl,
  });

  /// OSM editing API (api.openstreetmap.org)
  /// Policy: max 2 concurrent download threads.
  /// https://operations.osmfoundation.org/policies/api/
  const ServicePolicy.osmEditingApi()
      : maxConcurrentRequests = 2,
        minRequestInterval = null,
        allowsOfflineDownload = true, // n/a for API
        requiresClientCaching = false,
        minCacheTtl = null,
        attributionUrl = null;

  /// OSM tile server (tile.openstreetmap.org)
  /// Policy: no offline/bulk downloading, min 7-day cache, must honor cache headers.
  /// Concurrency managed by flutter_map's NetworkTileProvider.
  /// https://operations.osmfoundation.org/policies/tiles/
  const ServicePolicy.osmTileServer()
      : maxConcurrentRequests = 0, // managed by flutter_map
        minRequestInterval = null,
        allowsOfflineDownload = false,
        requiresClientCaching = true,
        minCacheTtl = const Duration(days: 7),
        attributionUrl = 'https://www.openstreetmap.org/copyright';

  /// Nominatim geocoding (nominatim.openstreetmap.org)
  /// Policy: max 1 req/sec, single machine only, results must be cached.
  /// https://operations.osmfoundation.org/policies/nominatim/
  const ServicePolicy.nominatim()
      : maxConcurrentRequests = 1,
        minRequestInterval = const Duration(seconds: 1),
        allowsOfflineDownload = true, // n/a for geocoding
        requiresClientCaching = true,
        minCacheTtl = null,
        attributionUrl = 'https://www.openstreetmap.org/copyright';

  /// Overpass API (overpass-api.de)
  /// Concurrency and rate limiting managed by PR #114's _AsyncSemaphore.
  const ServicePolicy.overpass()
      : maxConcurrentRequests = 0, // managed by NodeDataManager
        minRequestInterval = null, // managed by NodeDataManager
        allowsOfflineDownload = true, // n/a for data queries
        requiresClientCaching = false,
        minCacheTtl = null,
        attributionUrl = null;

  /// TagInfo API (taginfo.openstreetmap.org)
  const ServicePolicy.tagInfo()
      : maxConcurrentRequests = 2,
        minRequestInterval = null,
        allowsOfflineDownload = true, // n/a
        requiresClientCaching = true, // already cached in NSIService
        minCacheTtl = null,
        attributionUrl = null;

  /// Bing Maps tiles (*.tiles.virtualearth.net)
  const ServicePolicy.bingTiles()
      : maxConcurrentRequests = 0, // managed by flutter_map
        minRequestInterval = null,
        allowsOfflineDownload = true, // check Bing ToS separately
        requiresClientCaching = false,
        minCacheTtl = null,
        attributionUrl = null;

  /// Mapbox tiles (api.mapbox.com)
  const ServicePolicy.mapboxTiles()
      : maxConcurrentRequests = 0, // managed by flutter_map
        minRequestInterval = null,
        allowsOfflineDownload = true, // permitted with valid token
        requiresClientCaching = false,
        minCacheTtl = null,
        attributionUrl = null;

  /// Custom/self-hosted service — permissive defaults.
  const ServicePolicy.custom({
    int maxConcurrent = 8,
    bool allowsOffline = true,
    Duration? minInterval,
    String? attribution,
  })  : maxConcurrentRequests = maxConcurrent,
        minRequestInterval = minInterval,
        allowsOfflineDownload = allowsOffline,
        requiresClientCaching = false,
        minCacheTtl = null,
        attributionUrl = attribution;

  @override
  String toString() => 'ServicePolicy('
      'maxConcurrent: $maxConcurrentRequests, '
      'minInterval: $minRequestInterval, '
      'offlineDownload: $allowsOfflineDownload, '
      'clientCaching: $requiresClientCaching, '
      'minCacheTtl: $minCacheTtl, '
      'attributionUrl: $attributionUrl)';
}

/// Resolves URLs and tile providers to their applicable [ServicePolicy].
///
/// Built-in patterns cover all OSMF official services and common third-party
/// tile providers. Custom overrides can be registered for self-hosted endpoints
/// via [registerCustomPolicy].
class ServicePolicyResolver {
  /// Host → ServiceType mapping for known services.
  static final Map<String, ServiceType> _hostPatterns = {
    'api.openstreetmap.org': ServiceType.osmEditingApi,
    'api06.dev.openstreetmap.org': ServiceType.osmEditingApi,
    'master.apis.dev.openstreetmap.org': ServiceType.osmEditingApi,
    'tile.openstreetmap.org': ServiceType.osmTileServer,
    'nominatim.openstreetmap.org': ServiceType.nominatim,
    'overpass-api.de': ServiceType.overpass,
    'taginfo.openstreetmap.org': ServiceType.tagInfo,
    'tiles.virtualearth.net': ServiceType.bingTiles,
    'api.mapbox.com': ServiceType.mapboxTiles,
  };

  /// ServiceType → policy mapping.
  static final Map<ServiceType, ServicePolicy> _policies = {
    ServiceType.osmEditingApi: const ServicePolicy.osmEditingApi(),
    ServiceType.osmTileServer: const ServicePolicy.osmTileServer(),
    ServiceType.nominatim: const ServicePolicy.nominatim(),
    ServiceType.overpass: const ServicePolicy.overpass(),
    ServiceType.tagInfo: const ServicePolicy.tagInfo(),
    ServiceType.bingTiles: const ServicePolicy.bingTiles(),
    ServiceType.mapboxTiles: const ServicePolicy.mapboxTiles(),
    ServiceType.custom: const ServicePolicy(),
  };

  /// Custom host overrides registered at runtime (for self-hosted services).
  static final Map<String, ServicePolicy> _customOverrides = {};

  /// Resolve a URL to its applicable [ServicePolicy].
  ///
  /// Checks custom overrides first, then built-in host patterns. Falls back
  /// to [ServicePolicy.custom] for unrecognized hosts.
  static ServicePolicy resolve(String url) {
    final host = _extractHost(url);
    if (host == null) return const ServicePolicy();

    // Check custom overrides first (exact or subdomain matching)
    for (final entry in _customOverrides.entries) {
      if (host == entry.key || host.endsWith('.${entry.key}')) {
        return entry.value;
      }
    }

    // Check built-in patterns (support subdomain matching)
    for (final entry in _hostPatterns.entries) {
      if (host == entry.key || host.endsWith('.${entry.key}')) {
        return _policies[entry.value] ?? const ServicePolicy();
      }
    }

    return const ServicePolicy();
  }

  /// Resolve a URL to its [ServiceType].
  ///
  /// Returns [ServiceType.custom] for unrecognized hosts.
  static ServiceType resolveType(String url) {
    final host = _extractHost(url);
    if (host == null) return ServiceType.custom;

    // Check custom overrides first — a registered custom policy means
    // the host is treated as ServiceType.custom with custom rules.
    for (final entry in _customOverrides.entries) {
      if (host == entry.key || host.endsWith('.${entry.key}')) {
        return ServiceType.custom;
      }
    }

    for (final entry in _hostPatterns.entries) {
      if (host == entry.key || host.endsWith('.${entry.key}')) {
        return entry.value;
      }
    }

    return ServiceType.custom;
  }

  /// Look up the [ServicePolicy] for a known [ServiceType].
  static ServicePolicy resolveByType(ServiceType type) =>
      _policies[type] ?? const ServicePolicy();

  /// Register a custom policy override for a host pattern.
  ///
  /// Use this to configure self-hosted services:
  /// ```dart
  /// ServicePolicyResolver.registerCustomPolicy(
  ///   'tiles.myserver.com',
  ///   ServicePolicy.custom(allowsOffline: true, maxConcurrent: 20),
  /// );
  /// ```
  static void registerCustomPolicy(String hostPattern, ServicePolicy policy) {
    _customOverrides[hostPattern] = policy;
  }

  /// Remove a custom policy override.
  static void removeCustomPolicy(String hostPattern) {
    _customOverrides.remove(hostPattern);
  }

  /// Clear all custom policy overrides (useful for testing).
  static void clearCustomPolicies() {
    _customOverrides.clear();
  }

  /// Extract the host from a URL or URL template.
  static String? _extractHost(String url) {
    // Handle URL templates like 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
    // and subdomain templates like 'https://ecn.t{0_3}.tiles.virtualearth.net/...'
    try {
      // Strip template variables from subdomain part for parsing
      final cleaned = url
          .replaceAll(RegExp(r'\{0_3\}'), '0')
          .replaceAll(RegExp(r'\{1_4\}'), '1')
          .replaceAll(RegExp(r'\{quadkey\}'), 'quadkey')
          .replaceAll(RegExp(r'\{z\}'), '0')
          .replaceAll(RegExp(r'\{x\}'), '0')
          .replaceAll(RegExp(r'\{y\}'), '0')
          .replaceAll(RegExp(r'\{api_key\}'), 'key');
      return Uri.parse(cleaned).host.toLowerCase();
    } catch (_) {
      return null;
    }
  }
}

/// Reusable per-service rate limiter and concurrency controller.
///
/// Enforces the rate limits and concurrency constraints defined in each
/// service's [ServicePolicy]. Call [acquire] before making a request and
/// [release] after the request completes.
///
/// Only manages services whose policies have [ServicePolicy.maxConcurrentRequests] > 0
/// and/or [ServicePolicy.minRequestInterval] set. Services managed elsewhere
/// (flutter_map, PR #114) are passed through without blocking.
class ServiceRateLimiter {
  /// Per-service timestamps of the last acquired request slot / request start
  /// (used for rate limiting in [acquire], not updated on completion).
  static final Map<ServiceType, DateTime> _lastRequestTime = {};

  /// Per-service concurrency semaphores.
  static final Map<ServiceType, _Semaphore> _semaphores = {};

  /// Acquire a slot: wait for rate limit compliance, then take a connection slot.
  ///
  /// Blocks if:
  /// 1. The minimum interval between requests hasn't elapsed yet, or
  /// 2. All concurrent connection slots are in use.
  static Future<void> acquire(ServiceType service) async {
    final policy = ServicePolicyResolver.resolveByType(service);

    // Concurrency: acquire semaphore slot first, so only one caller at a
    // time proceeds to the rate-limit check. This prevents concurrent
    // callers from bypassing the min interval when _lastRequestTime is
    // still null or stale.
    _Semaphore? semaphore;
    if (policy.maxConcurrentRequests > 0) {
      semaphore = _semaphores.putIfAbsent(
        service,
        () => _Semaphore(policy.maxConcurrentRequests),
      );
      await semaphore.acquire();
    }

    try {
      // Rate limit: wait if we sent a request too recently
      if (policy.minRequestInterval != null) {
        final lastTime = _lastRequestTime[service];
        if (lastTime != null) {
          final elapsed = DateTime.now().difference(lastTime);
          final remaining = policy.minRequestInterval! - elapsed;
          if (remaining > Duration.zero) {
            debugPrint('[ServiceRateLimiter] Throttling $service for ${remaining.inMilliseconds}ms');
            await Future.delayed(remaining);
          }
        }
      }

      // Record request time
      _lastRequestTime[service] = DateTime.now();
    } catch (_) {
      // Release the semaphore slot if the rate-limit delay fails,
      // to avoid permanently leaking a slot.
      semaphore?.release();
      rethrow;
    }
  }

  /// Release a connection slot after request completes.
  static void release(ServiceType service) {
    _semaphores[service]?.release();
  }

  /// Reset all rate limiter state (for testing).
  @visibleForTesting
  static void reset() {
    _lastRequestTime.clear();
    _semaphores.clear();
  }
}

/// Simple async counting semaphore for concurrency limiting.
class _Semaphore {
  final int _maxCount;
  int _currentCount = 0;
  final List<Completer<void>> _waiters = [];

  _Semaphore(this._maxCount);

  Future<void> acquire() async {
    if (_currentCount < _maxCount) {
      _currentCount++;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeAt(0);
      next.complete();
    } else if (_currentCount > 0) {
      _currentCount--;
    } else {
      throw StateError(
        'Semaphore.release() called more times than acquire(); '
        'currentCount is already zero.',
      );
    }
  }
}
