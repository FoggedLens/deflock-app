import 'dart:math';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
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



/// Fetches a tile from any remote provider, with in-memory retries/backoff, and global concurrency limit.
/// Returns tile image bytes, or throws on persistent failure.
Future<List<int>> fetchRemoteTile({
  required int z,
  required int x,
  required int y,
  required String url,
}) async {
  const int maxAttempts = kTileFetchMaxAttempts;
  int attempt = 0;
  final random = Random();
  final delays = [
    kTileFetchInitialDelayMs + random.nextInt(kTileFetchJitter1Ms),
    kTileFetchSecondDelayMs + random.nextInt(kTileFetchJitter2Ms),
    kTileFetchThirdDelayMs + random.nextInt(kTileFetchJitter3Ms),
  ];
  
  final hostInfo = Uri.parse(url).host; // For logging

  while (true) {
    await _tileFetchSemaphore.acquire();
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
      
      final delay = delays[attempt - 1].clamp(0, 60000);
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

/// Simple counting semaphore, suitable for single-thread Flutter concurrency
class _SimpleSemaphore {
  final int _max;
  int _current = 0;
  final List<VoidCallback> _queue = [];
  _SimpleSemaphore(this._max);

  Future<void> acquire() async {
    if (_current < _max) {
      _current++;
      return;
    } else {
      final c = Completer<void>();
      _queue.add(() => c.complete());
      await c.future;
    }
  }

  void release() {
    if (_queue.isNotEmpty) {
      final callback = _queue.removeAt(0);
      callback();
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
}