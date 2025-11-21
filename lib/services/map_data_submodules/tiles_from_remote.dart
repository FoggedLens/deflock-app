import 'dart:math';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:deflockapp/dev_config.dart';
import '../network_status.dart';

/// Global semaphore to limit simultaneous tile fetches
final _tileFetchSemaphore = _SimpleSemaphore(4); // Max 4 concurrent

/// Clear queued tile requests when map view changes significantly
void clearRemoteTileQueue() {
  final clearedCount = _tileFetchSemaphore.clearQueue();
  // Only log if we actually cleared something significant
  if (clearedCount > 5) {
    debugPrint('[RemoteTiles] Cleared $clearedCount queued tile requests');
  }
}

/// Clear only tile requests that are no longer visible in the given bounds
void clearRemoteTileQueueSelective(LatLngBounds currentBounds) {
  final clearedCount = _tileFetchSemaphore.clearStaleRequests((z, x, y) {
    // Return true if tile should be cleared (i.e., is NOT visible)
    return !_isTileVisible(z, x, y, currentBounds);
  });
  
  if (clearedCount > 0) {
    debugPrint('[RemoteTiles] Selectively cleared $clearedCount non-visible tile requests');
  }
}

/// Calculate retry delay using configurable backoff strategy.
/// Uses: initialDelay * (multiplier ^ (attempt - 1)) + randomJitter, capped at maxDelay
int _calculateRetryDelay(int attempt, Random random) {
  // Calculate exponential backoff: initialDelay * (multiplier ^ (attempt - 1))
  final baseDelay = (dev.kTileFetchInitialDelayMs * 
    pow(dev.kTileFetchBackoffMultiplier, attempt - 1)).round();
  
  // Add random jitter to avoid thundering herd
  final jitter = random.nextInt(dev.kTileFetchRandomJitterMs + 1);
  
  // Apply max delay cap
  return (baseDelay + jitter).clamp(0, dev.kTileFetchMaxDelayMs);
}

/// Convert tile coordinates to lat/lng bounds for spatial filtering
class _TileBounds {
  final double north, south, east, west;
  _TileBounds({required this.north, required this.south, required this.east, required this.west});
}

/// Calculate the lat/lng bounds for a given tile
_TileBounds _tileToBounds(int z, int x, int y) {
  final n = pow(2, z);
  final lon1 = (x / n) * 360.0 - 180.0;
  final lon2 = ((x + 1) / n) * 360.0 - 180.0;
  final lat1 = _yToLatitude(y, z);
  final lat2 = _yToLatitude(y + 1, z);
  
  return _TileBounds(
    north: max(lat1, lat2),
    south: min(lat1, lat2),
    east: max(lon1, lon2),
    west: min(lon1, lon2),
  );
}

/// Convert tile Y coordinate to latitude
double _yToLatitude(int y, int z) {
  final n = pow(2, z);
  final latRad = atan(_sinh(pi * (1 - 2 * y / n)));
  return latRad * 180.0 / pi;
}

/// Hyperbolic sine function: sinh(x) = (e^x - e^(-x)) / 2
double _sinh(double x) {
  return (exp(x) - exp(-x)) / 2;
}

/// Check if a tile intersects with the current view bounds
bool _isTileVisible(int z, int x, int y, LatLngBounds viewBounds) {
  final tileBounds = _tileToBounds(z, x, y);
  
  // Check if tile bounds intersect with view bounds
  return !(tileBounds.east < viewBounds.west ||
           tileBounds.west > viewBounds.east ||
           tileBounds.north < viewBounds.south ||
           tileBounds.south > viewBounds.north);
}



/// Fetches a tile from any remote provider, with in-memory retries/backoff, and global concurrency limit.
/// Returns tile image bytes, or throws on persistent failure.
Future<List<int>> fetchRemoteTile({
  required int z,
  required int x,
  required int y,
  required String url,
}) async {
  final int maxAttempts = dev.dev.kTileFetchMaxAttempts;
  int attempt = 0;
  final random = Random();
  final hostInfo = Uri.parse(url).host; // For logging

  while (true) {
    await _tileFetchSemaphore.acquire(z: z, x: x, y: y);
    try {
      // Only log on first attempt or errors
      if (attempt == 1) {
        debugPrint('[fetchRemoteTile] Fetching $z/$x/$y from $hostInfo');
      }
      attempt++;
      final resp = await http.get(Uri.parse(url));
      
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        // Success - no logging for normal operation
        NetworkStatus.instance.reportOsmTileSuccess(); // Generic tile server reporting
        return resp.bodyBytes;
      } else {
        debugPrint('[fetchRemoteTile] FAIL $z/$x/$y from $hostInfo: code=${resp.statusCode}, bytes=${resp.bodyBytes.length}');
        NetworkStatus.instance.reportOsmTileIssue(); // Generic tile server reporting
        throw HttpException('Failed to fetch tile $z/$x/$y from $hostInfo: status ${resp.statusCode}');
      }
    } catch (e) {
      // Report network issues on connection errors
      if (e.toString().contains('Connection refused') || 
          e.toString().contains('Connection timed out') ||
          e.toString().contains('Connection reset')) {
        NetworkStatus.instance.reportOsmTileIssue(); // Generic tile server reporting
      }
      
      if (attempt >= maxAttempts) {
        debugPrint("[fetchRemoteTile] Failed for $z/$x/$y from $hostInfo after $attempt attempts: $e");
        rethrow;
      }
      
      final delay = _calculateRetryDelay(attempt, random);
      if (attempt == 1) {
        debugPrint("[fetchRemoteTile] Attempt $attempt for $z/$x/$y from $hostInfo failed: $e. Retrying in ${delay}ms.");
      }
      await Future.delayed(Duration(milliseconds: delay));
    } finally {
      _tileFetchSemaphore.release();
    }
  }
}

/// Legacy function for backward compatibility
@Deprecated('Use fetchRemoteTile instead')
Future<List<int>> fetchOSMTile({
  required int z,
  required int x,
  required int y,
}) async {
  return fetchRemoteTile(
    z: z,
    x: x,
    y: y,
    url: 'https://tile.openstreetmap.org/$z/$x/$y.png',
  );
}

/// Enhanced tile request entry that tracks coordinates for spatial filtering
class _TileRequest {
  final int z, x, y;
  final VoidCallback callback;
  
  _TileRequest({required this.z, required this.x, required this.y, required this.callback});
}

/// Spatially-aware counting semaphore for tile requests
class _SimpleSemaphore {
  final int _max;
  int _current = 0;
  final List<_TileRequest> _queue = [];
  _SimpleSemaphore(this._max);

  Future<void> acquire({int? z, int? x, int? y}) async {
    if (_current < _max) {
      _current++;
      return;
    } else {
      final c = Completer<void>();
      final request = _TileRequest(
        z: z ?? -1, 
        x: x ?? -1, 
        y: y ?? -1, 
        callback: () => c.complete(),
      );
      _queue.add(request);
      await c.future;
    }
  }

  void release() {
    if (_queue.isNotEmpty) {
      final request = _queue.removeAt(0);
      request.callback();
    } else {
      _current--;
    }
  }

  /// Clear all queued requests (call when view changes significantly)
  int clearQueue() {
    final clearedCount = _queue.length;
    _queue.clear();
    return clearedCount;
  }
  
  /// Clear only tiles that don't pass the visibility filter
  int clearStaleRequests(bool Function(int z, int x, int y) isStale) {
    final initialCount = _queue.length;
    _queue.removeWhere((request) => isStale(request.z, request.x, request.y));
    final clearedCount = initialCount - _queue.length;
    
    if (clearedCount > 0) {
      debugPrint('[SimpleSemaphore] Cleared $clearedCount stale tile requests, kept ${_queue.length}');
    }
    
    return clearedCount;
  }
}