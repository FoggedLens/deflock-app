import 'dart:math';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Global semaphore to limit simultaneous tile fetches
final _tileFetchSemaphore = _SimpleSemaphore(4); // Max 4 concurrent

/// Fetches a tile from OSM, with in-memory retries/backoff, and global concurrency limit.
/// Returns tile image bytes, or throws on persistent failure.
import '../../app_state.dart';

Future<List<int>> fetchOSMTile({
  required int z,
  required int x,
  required int y,
}) async {
  if (AppState().offlineMode) {
    print('[fetchOSMTile] BLOCKED by offline mode ($z/$x/$y)');
    throw Exception('Offline mode enabled—cannot fetch OSM tile.');
  }
  final url = 'https://tile.openstreetmap.org/$z/$x/$y.png';
  const int maxAttempts = 3;
  int attempt = 0;
  final random = Random();
  final delays = [
    4000 + random.nextInt(1000),         // 4-5s after 1st failure
    15000 + random.nextInt(4000),       // 15-19s after 2nd
    60000 + random.nextInt(5000),       // 60-65s after 3rd
  ];
  while (true) {
    await _tileFetchSemaphore.acquire();
    try {
      print('[fetchOSMTile] FETCH $z/$x/$y');
      attempt++;
      final resp = await http.get(Uri.parse(url));
      print('[fetchOSMTile] HTTP ${resp.statusCode} for $z/$x/$y, length=${resp.bodyBytes.length}');
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        print('[fetchOSMTile] SUCCESS $z/$x/$y');
        return resp.bodyBytes;
      } else {
        print('[fetchOSMTile] FAIL $z/$x/$y: code=${resp.statusCode}, bytes=${resp.bodyBytes.length}');
        throw HttpException('Failed to fetch tile $z/$x/$y: status ${resp.statusCode}');
      }
    } catch (e) {
      print('[fetchOSMTile] Exception $z/$x/$y: $e');
      if (attempt >= maxAttempts) {
        print("[fetchOSMTile] Failed for $z/$x/$y after $attempt attempts: $e");
        rethrow;
      }
      final delay = delays[attempt - 1].clamp(0, 60000);
      print("[fetchOSMTile] Attempt $attempt for $z/$x/$y failed: $e. Retrying in ${delay}ms.");
      await Future.delayed(Duration(milliseconds: delay));
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
}