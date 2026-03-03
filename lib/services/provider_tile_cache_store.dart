import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Per-provider tile cache implementing flutter_map's [MapCachingProvider].
///
/// Each instance manages an isolated cache directory with:
/// - Deterministic UUID v5 key generation from tile URLs
/// - Optional TTL override from [ServicePolicy.minCacheTtl]
/// - Configurable max cache size with oldest-modified eviction
///
/// Files are stored as `{key}.tile` (image bytes) and `{key}.meta` (JSON
/// metadata containing staleAt, lastModified, etag).
class ProviderTileCacheStore implements MapCachingProvider {
  final String cacheDirectory;
  final int maxCacheBytes;
  final Duration? overrideFreshAge;

  static const _uuid = Uuid();

  /// Running estimate of cache size in bytes. Initialized lazily on first
  /// [putTile] call to avoid blocking construction.
  int? _estimatedSize;

  /// Throttle: don't re-scan more than once per minute.
  DateTime? _lastPruneCheck;

  /// One-shot latch for lazy directory creation (safe under concurrent calls).
  Completer<void>? _directoryReady;

  /// Guard against concurrent eviction runs.
  bool _isEvicting = false;

  ProviderTileCacheStore({
    required this.cacheDirectory,
    this.maxCacheBytes = 500 * 1024 * 1024, // 500 MB default
    this.overrideFreshAge,
  });

  @override
  bool get isSupported => true;

  @override
  Future<CachedMapTile?> getTile(String url) async {
    final key = _keyFor(url);
    final tileFile = File(p.join(cacheDirectory, '$key.tile'));
    final metaFile = File(p.join(cacheDirectory, '$key.meta'));

    try {
      final bytes = await tileFile.readAsBytes();
      final metaJson = json.decode(await metaFile.readAsString())
          as Map<String, dynamic>;

      final metadata = CachedMapTileMetadata(
        staleAt: DateTime.fromMillisecondsSinceEpoch(
          metaJson['staleAt'] as int,
          isUtc: true,
        ),
        lastModified: metaJson['lastModified'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                metaJson['lastModified'] as int,
                isUtc: true,
              )
            : null,
        etag: metaJson['etag'] as String?,
      );

      return (bytes: bytes, metadata: metadata);
    } on PathNotFoundException {
      return null;
    } catch (e) {
      throw CachedMapTileReadFailure(
        url: url,
        description: 'Failed to read cached tile',
        originalError: e,
      );
    }
  }

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    await _ensureDirectory();

    final key = _keyFor(url);
    final tileFile = File(p.join(cacheDirectory, '$key.tile'));
    final metaFile = File(p.join(cacheDirectory, '$key.meta'));

    // Apply minimum TTL override if configured (e.g., OSM 7-day minimum).
    // Use the later of server-provided staleAt and our minimum to avoid
    // accidentally shortening a longer server-provided freshness lifetime.
    final effectiveMetadata = overrideFreshAge != null
        ? (() {
            final overrideStaleAt = DateTime.timestamp().add(overrideFreshAge!);
            final staleAt = metadata.staleAt.isAfter(overrideStaleAt)
                ? metadata.staleAt
                : overrideStaleAt;
            return CachedMapTileMetadata(
              staleAt: staleAt,
              lastModified: metadata.lastModified,
              etag: metadata.etag,
            );
          })()
        : metadata;

    final metaJson = json.encode({
      'staleAt': effectiveMetadata.staleAt.millisecondsSinceEpoch,
      'lastModified':
          effectiveMetadata.lastModified?.millisecondsSinceEpoch,
      'etag': effectiveMetadata.etag,
    });

    // Write .tile before .meta: if we crash between the two writes, the
    // read path's both-must-exist check sees a miss rather than an orphan .meta.
    if (bytes != null) {
      await tileFile.writeAsBytes(bytes);
    }
    await metaFile.writeAsString(metaJson);

    // Reset size estimate so it resyncs from disk on next check.
    // This avoids drift from overwrites where the old size isn't subtracted.
    _estimatedSize = null;

    // Schedule lazy size check
    _scheduleEvictionCheck();
  }

  /// Ensure the cache directory exists (lazy creation on first write).
  ///
  /// Uses a Completer latch so concurrent callers share a single create().
  /// Safe under Dart's single-threaded event loop: the null check and
  /// assignment happen in the same synchronous block with no `await`
  /// between them, so no other microtask can interleave.
  Future<void> _ensureDirectory() {
    if (_directoryReady == null) {
      final completer = Completer<void>();
      _directoryReady = completer;
      Directory(cacheDirectory).create(recursive: true).then(
        (_) => completer.complete(),
        onError: (Object error, StackTrace stackTrace) {
          // Reset latch on error so later calls can retry directory creation.
          if (identical(_directoryReady, completer)) {
            _directoryReady = null;
          }
          completer.completeError(error, stackTrace);
        },
      );
    }
    return _directoryReady!.future;
  }

  /// Generate a cache key from URL using UUID v5 (same as flutter_map built-in).
  static String _keyFor(String url) => _uuid.v5(Namespace.url.value, url);

  /// Estimate total cache size (lazy, first call scans directory).
  Future<int> _getEstimatedSize() async {
    if (_estimatedSize != null) return _estimatedSize!;

    final dir = Directory(cacheDirectory);
    if (!await dir.exists()) {
      _estimatedSize = 0;
      return 0;
    }

    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    _estimatedSize = total;
    return total;
  }

  /// Schedule eviction if we haven't checked recently.
  void _scheduleEvictionCheck() {
    final now = DateTime.now();
    if (_lastPruneCheck != null &&
        now.difference(_lastPruneCheck!) < const Duration(minutes: 1)) {
      return;
    }
    _lastPruneCheck = now;

    // Fire-and-forget: eviction is best-effort background work.
    // _estimatedSize may be momentarily stale between eviction start and
    // completion, but this is acceptable — the guard only needs to be
    // approximately correct to prevent unbounded growth, and the throttle
    // ensures we re-check within a minute.
    // ignore: discarded_futures
    _evictIfNeeded();
  }

  /// Evict oldest-modified tiles if cache exceeds size limit.
  ///
  /// Sorts by file mtime (oldest first), not by last access — true LRU would
  /// require touching files on every [getTile] read, adding I/O on the hot
  /// path.  In practice write-recency tracks usage well because tiles are
  /// immutable and flutter_map holds visible tiles in memory.
  ///
  /// Guarded by [_isEvicting] to prevent concurrent runs from corrupting
  /// [_estimatedSize].
  Future<void> _evictIfNeeded() async {
    if (_isEvicting) return;
    _isEvicting = true;
    try {
      final currentSize = await _getEstimatedSize();
      if (currentSize <= maxCacheBytes) return;

      final dir = Directory(cacheDirectory);
      if (!await dir.exists()) return;

      // Collect all files, separating .tile and .meta for eviction + orphan cleanup.
      final tileFiles = <File>[];
      final metaFiles = <String>{};
      await for (final entity in dir.list()) {
        if (entity is File) {
          if (entity.path.endsWith('.tile')) {
            tileFiles.add(entity);
          } else if (entity.path.endsWith('.meta')) {
            metaFiles.add(p.basenameWithoutExtension(entity.path));
          }
        }
      }

      if (tileFiles.isEmpty) return;

      // Sort by modification time, oldest first
      final stats = await Future.wait(
        tileFiles.map((f) async => (file: f, stat: await f.stat())),
      );
      stats.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));

      var freedBytes = 0;
      final targetSize = (maxCacheBytes * 0.8).toInt(); // Free down to 80%
      final evictedKeys = <String>{};

      for (final entry in stats) {
        if (currentSize - freedBytes <= targetSize) break;

        final key = p.basenameWithoutExtension(entry.file.path);
        final metaFile = File(p.join(cacheDirectory, '$key.meta'));

        try {
          await entry.file.delete();
          freedBytes += entry.stat.size;
          evictedKeys.add(key);
          if (await metaFile.exists()) {
            final metaStat = await metaFile.stat();
            await metaFile.delete();
            freedBytes += metaStat.size;
          }
        } catch (e) {
          debugPrint('[ProviderTileCacheStore] Failed to evict $key: $e');
        }
      }

      // Clean up orphan .meta files (no matching .tile file).
      // Exclude keys we just evicted — their .tile is gone so they're orphans.
      final remainingTileKeys = tileFiles
          .map((f) => p.basenameWithoutExtension(f.path))
          .toSet()
        ..removeAll(evictedKeys);
      for (final metaKey in metaFiles) {
        if (!remainingTileKeys.contains(metaKey)) {
          try {
            final orphan = File(p.join(cacheDirectory, '$metaKey.meta'));
            final orphanStat = await orphan.stat();
            await orphan.delete();
            freedBytes += orphanStat.size;
          } catch (_) {
            // Best-effort cleanup
          }
        }
      }

      _estimatedSize = currentSize - freedBytes;
      debugPrint(
        '[ProviderTileCacheStore] Evicted ${freedBytes ~/ 1024}KB '
        'from $cacheDirectory',
      );
    } catch (e) {
      debugPrint('[ProviderTileCacheStore] Eviction error: $e');
    } finally {
      _isEvicting = false;
    }
  }

  /// Delete all cached tiles in this store's directory.
  Future<void> clear() async {
    final dir = Directory(cacheDirectory);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _estimatedSize = null;
    _directoryReady = null; // Allow lazy re-creation
  }

  /// Get the current estimated cache size in bytes.
  Future<int> get estimatedSizeBytes => _getEstimatedSize();

  /// Force an eviction check, bypassing the throttle.
  /// Only exposed for testing — production code uses [_scheduleEvictionCheck].
  @visibleForTesting
  Future<void> forceEviction() => _evictIfNeeded();
}
