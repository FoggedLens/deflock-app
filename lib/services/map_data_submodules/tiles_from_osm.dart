import 'dart:math';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flock_map_app/dev_config.dart';
import '../network_status.dart';

/// Global semaphore to limit simultaneous tile fetches
final _tileFetchSemaphore = _SimpleSemaphore(4); // Max 4 concurrent

/// Cancellation token to invalidate all pending requests
int _globalCancelToken = 0;

/// Clear queued tile requests and cancel all retries
void clearOSMTileQueue() {
  final oldToken = _globalCancelToken;
  _globalCancelToken++; // Invalidate all pending requests and retries
  final clearedCount = _tileFetchSemaphore.clearQueue();
  debugPrint('[OSMTiles] Cancel token: $oldToken -> $_globalCancelToken, cleared $clearedCount queued');
}

/// Fetches a tile from OSM, with in-memory retries/backoff, and global concurrency limit.
/// Returns tile image bytes, or throws on persistent failure.
Future<List<int>> fetchOSMTile({
  required int z,
  required int x,
  required int y,
}) async {
  final url = 'https://tile.openstreetmap.org/$z/$x/$y.png';
  const int maxAttempts = kTileFetchMaxAttempts;
  int attempt = 0;
  final random = Random();
  final delays = [
    kTileFetchInitialDelayMs + random.nextInt(kTileFetchJitter1Ms),
    kTileFetchSecondDelayMs + random.nextInt(kTileFetchJitter2Ms),
    kTileFetchThirdDelayMs + random.nextInt(kTileFetchJitter3Ms),
  ];
  
  // Remember the cancel token when we start this request
  final requestCancelToken = _globalCancelToken;
  print('[fetchOSMTile] START $z/$x/$y with token $requestCancelToken (global: $_globalCancelToken)');
  
  while (true) {
    // Check if this request was cancelled
    if (requestCancelToken != _globalCancelToken) {
      print('[fetchOSMTile] CANCELLED $z/$x/$y (token: $requestCancelToken vs $_globalCancelToken)');
      throw Exception('Tile request cancelled');
    }
    
    await _tileFetchSemaphore.acquire();
    try {
      print('[fetchOSMTile] FETCH $z/$x/$y');
      attempt++;
      final resp = await http.get(Uri.parse(url));
      print('[fetchOSMTile] HTTP ${resp.statusCode} for $z/$x/$y, length=${resp.bodyBytes.length}');
      
      // Check cancellation after HTTP request completes - this is the key check!
      if (requestCancelToken != _globalCancelToken) {
        print('[fetchOSMTile] CANCELLED $z/$x/$y after HTTP (token: $requestCancelToken vs $_globalCancelToken)');
        throw Exception('Tile request cancelled');
      }
      
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        print('[fetchOSMTile] SUCCESS $z/$x/$y');
        NetworkStatus.instance.reportOsmTileSuccess();
        return resp.bodyBytes;
      } else {
        print('[fetchOSMTile] FAIL $z/$x/$y: code=${resp.statusCode}, bytes=${resp.bodyBytes.length}');
        NetworkStatus.instance.reportOsmTileIssue();
        throw HttpException('Failed to fetch tile $z/$x/$y: status ${resp.statusCode}');
      }
    } catch (e) {
      // Don't retry cancelled requests
      if (e.toString().contains('cancelled')) {
        rethrow;
      }
      
      print('[fetchOSMTile] Exception $z/$x/$y: $e');
      
      // Report network issues on connection errors
      if (e.toString().contains('Connection refused') || 
          e.toString().contains('Connection timed out') ||
          e.toString().contains('Connection reset')) {
        NetworkStatus.instance.reportOsmTileIssue();
      }
      
      if (attempt >= maxAttempts) {
        print("[fetchOSMTile] Failed for $z/$x/$y after $attempt attempts: $e");
        rethrow;
      }
      
      final delay = delays[attempt - 1].clamp(0, 60000);
      print("[fetchOSMTile] Attempt $attempt for $z/$x/$y failed: $e. Retrying in ${delay}ms.");
      
      // Check cancellation before and after delay
      if (requestCancelToken != _globalCancelToken) {
        print('[fetchOSMTile] CANCELLED $z/$x/$y before retry');
        throw Exception('Tile request cancelled');
      }
      
      await Future.delayed(Duration(milliseconds: delay));
      
      if (requestCancelToken != _globalCancelToken) {
        print('[fetchOSMTile] CANCELLED $z/$x/$y after retry delay');
        throw Exception('Tile request cancelled');
      }
    } finally {
      _tileFetchSemaphore.release();
    }
  }
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