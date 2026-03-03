import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:deflockapp/services/provider_tile_cache_store.dart';
import 'package:deflockapp/services/provider_tile_cache_manager.dart';
import 'package:deflockapp/services/service_policy.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tile_cache_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    await ProviderTileCacheManager.resetAll();
  });

  group('ProviderTileCacheStore', () {
    late ProviderTileCacheStore store;

    setUp(() {
      store = ProviderTileCacheStore(
        cacheDirectory: tempDir.path,
      );
    });

    test('isSupported is true', () {
      expect(store.isSupported, isTrue);
    });

    test('getTile returns null for uncached URL', () async {
      final result = await store.getTile('https://tile.example.com/1/2/3.png');
      expect(result, isNull);
    });

    test('putTile and getTile round-trip', () async {
      const url = 'https://tile.example.com/1/2/3.png';
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final staleAt = DateTime.utc(2026, 3, 1);
      final metadata = CachedMapTileMetadata(
        staleAt: staleAt,
        lastModified: DateTime.utc(2026, 2, 20),
        etag: '"abc123"',
      );

      await store.putTile(url: url, metadata: metadata, bytes: bytes);

      final cached = await store.getTile(url);
      expect(cached, isNotNull);
      expect(cached!.bytes, equals(bytes));
      expect(
        cached.metadata.staleAt.millisecondsSinceEpoch,
        equals(staleAt.millisecondsSinceEpoch),
      );
      expect(cached.metadata.etag, equals('"abc123"'));
      expect(cached.metadata.lastModified, isNotNull);
    });

    test('putTile without bytes updates metadata only', () async {
      const url = 'https://tile.example.com/1/2/3.png';
      final bytes = Uint8List.fromList([1, 2, 3]);
      final metadata1 = CachedMapTileMetadata(
        staleAt: DateTime.utc(2026, 3, 1),
        lastModified: null,
        etag: '"v1"',
      );

      // Write with bytes first
      await store.putTile(url: url, metadata: metadata1, bytes: bytes);

      // Update metadata only
      final metadata2 = CachedMapTileMetadata(
        staleAt: DateTime.utc(2026, 4, 1),
        lastModified: null,
        etag: '"v2"',
      );
      await store.putTile(url: url, metadata: metadata2);

      final cached = await store.getTile(url);
      expect(cached, isNotNull);
      expect(cached!.bytes, equals(bytes)); // bytes unchanged
      expect(cached.metadata.etag, equals('"v2"')); // metadata updated
    });

    test('handles null lastModified and etag', () async {
      const url = 'https://tile.example.com/simple.png';
      final bytes = Uint8List.fromList([10, 20, 30]);
      final metadata = CachedMapTileMetadata(
        staleAt: DateTime.utc(2026, 3, 1),
        lastModified: null,
        etag: null,
      );

      await store.putTile(url: url, metadata: metadata, bytes: bytes);

      final cached = await store.getTile(url);
      expect(cached, isNotNull);
      expect(cached!.metadata.lastModified, isNull);
      expect(cached.metadata.etag, isNull);
    });

    test('creates cache directory lazily on first putTile', () async {
      final subDir = p.join(tempDir.path, 'lazy', 'nested');
      final lazyStore = ProviderTileCacheStore(cacheDirectory: subDir);

      // Directory should not exist yet
      expect(await Directory(subDir).exists(), isFalse);

      await lazyStore.putTile(
        url: 'https://example.com/tile.png',
        metadata: CachedMapTileMetadata(
          staleAt: DateTime.utc(2026, 3, 1),
          lastModified: null,
          etag: null,
        ),
        bytes: Uint8List.fromList([1]),
      );

      // Directory should now exist
      expect(await Directory(subDir).exists(), isTrue);
    });

    test('clear deletes all cached tiles', () async {
      // Write some tiles
      for (var i = 0; i < 5; i++) {
        await store.putTile(
          url: 'https://example.com/$i.png',
          metadata: CachedMapTileMetadata(
            staleAt: DateTime.utc(2026, 3, 1),
            lastModified: null,
            etag: null,
          ),
          bytes: Uint8List.fromList([i]),
        );
      }

      // Verify tiles exist
      expect(await store.getTile('https://example.com/0.png'), isNotNull);

      // Clear
      await store.clear();

      // Directory should be gone
      expect(await Directory(tempDir.path).exists(), isFalse);

      // getTile should return null (directory gone)
      expect(await store.getTile('https://example.com/0.png'), isNull);
    });
  });

  group('ProviderTileCacheStore TTL override', () {
    test('overrideFreshAge bumps staleAt forward', () async {
      final store = ProviderTileCacheStore(
        cacheDirectory: tempDir.path,
        overrideFreshAge: const Duration(days: 7),
      );

      const url = 'https://tile.example.com/osm.png';
      // Server says stale in 1 hour, but policy requires 7 days
      final serverMetadata = CachedMapTileMetadata(
        staleAt: DateTime.timestamp().add(const Duration(hours: 1)),
        lastModified: null,
        etag: null,
      );

      await store.putTile(
        url: url,
        metadata: serverMetadata,
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      final cached = await store.getTile(url);
      expect(cached, isNotNull);

      // staleAt should be ~7 days from now, not 1 hour
      final expectedMin = DateTime.timestamp().add(const Duration(days: 6));
      expect(cached!.metadata.staleAt.isAfter(expectedMin), isTrue);
    });

    test('without overrideFreshAge, server staleAt is preserved', () async {
      final store = ProviderTileCacheStore(
        cacheDirectory: tempDir.path,
        // No overrideFreshAge
      );

      const url = 'https://tile.example.com/bing.png';
      final serverStaleAt = DateTime.utc(2026, 3, 15, 12, 0);
      final serverMetadata = CachedMapTileMetadata(
        staleAt: serverStaleAt,
        lastModified: null,
        etag: null,
      );

      await store.putTile(
        url: url,
        metadata: serverMetadata,
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      final cached = await store.getTile(url);
      expect(cached, isNotNull);
      expect(
        cached!.metadata.staleAt.millisecondsSinceEpoch,
        equals(serverStaleAt.millisecondsSinceEpoch),
      );
    });
  });

  group('ProviderTileCacheStore isolation', () {
    test('separate directories do not interfere', () async {
      final dirA = p.join(tempDir.path, 'provider_a', 'type_1');
      final dirB = p.join(tempDir.path, 'provider_b', 'type_1');

      final storeA = ProviderTileCacheStore(cacheDirectory: dirA);
      final storeB = ProviderTileCacheStore(cacheDirectory: dirB);

      const url = 'https://tile.example.com/shared-url.png';
      final metadata = CachedMapTileMetadata(
        staleAt: DateTime.utc(2026, 3, 1),
        lastModified: null,
        etag: null,
      );

      await storeA.putTile(
        url: url,
        metadata: metadata,
        bytes: Uint8List.fromList([1, 1, 1]),
      );
      await storeB.putTile(
        url: url,
        metadata: metadata,
        bytes: Uint8List.fromList([2, 2, 2]),
      );

      final cachedA = await storeA.getTile(url);
      final cachedB = await storeB.getTile(url);

      expect(cachedA!.bytes, equals(Uint8List.fromList([1, 1, 1])));
      expect(cachedB!.bytes, equals(Uint8List.fromList([2, 2, 2])));
    });
  });

  group('ProviderTileCacheManager', () {
    test('getOrCreate returns same instance for same key', () {
      ProviderTileCacheManager.setBaseCacheDir(tempDir.path);

      final storeA = ProviderTileCacheManager.getOrCreate(
        providerId: 'osm',
        tileTypeId: 'street',
        policy: const ServicePolicy(),
      );
      final storeB = ProviderTileCacheManager.getOrCreate(
        providerId: 'osm',
        tileTypeId: 'street',
        policy: const ServicePolicy(),
      );

      expect(identical(storeA, storeB), isTrue);
    });

    test('getOrCreate returns different instances for different keys', () {
      ProviderTileCacheManager.setBaseCacheDir(tempDir.path);

      final storeA = ProviderTileCacheManager.getOrCreate(
        providerId: 'osm',
        tileTypeId: 'street',
        policy: const ServicePolicy(),
      );
      final storeB = ProviderTileCacheManager.getOrCreate(
        providerId: 'bing',
        tileTypeId: 'satellite',
        policy: const ServicePolicy(),
      );

      expect(identical(storeA, storeB), isFalse);
    });

    test('passes overrideFreshAge from policy.minCacheTtl', () {
      ProviderTileCacheManager.setBaseCacheDir(tempDir.path);

      final store = ProviderTileCacheManager.getOrCreate(
        providerId: 'osm',
        tileTypeId: 'street',
        policy: const ServicePolicy.osmTileServer(),
      );

      expect(store.overrideFreshAge, equals(const Duration(days: 7)));
    });

    test('custom maxCacheBytes is applied', () {
      ProviderTileCacheManager.setBaseCacheDir(tempDir.path);

      final store = ProviderTileCacheManager.getOrCreate(
        providerId: 'big',
        tileTypeId: 'tiles',
        policy: const ServicePolicy(),
        maxCacheBytes: 1024 * 1024 * 1024, // 1 GB
      );

      expect(store.maxCacheBytes, equals(1024 * 1024 * 1024));
    });

    test('resetAll clears all stores from registry', () async {
      ProviderTileCacheManager.setBaseCacheDir(tempDir.path);

      final storeBefore = ProviderTileCacheManager.getOrCreate(
        providerId: 'osm',
        tileTypeId: 'street',
        policy: const ServicePolicy(),
      );
      ProviderTileCacheManager.getOrCreate(
        providerId: 'bing',
        tileTypeId: 'satellite',
        policy: const ServicePolicy(),
      );

      await ProviderTileCacheManager.resetAll();

      // After reset, must set base dir again before creating stores
      ProviderTileCacheManager.setBaseCacheDir(tempDir.path);
      final storeAfter = ProviderTileCacheManager.getOrCreate(
        providerId: 'osm',
        tileTypeId: 'street',
        policy: const ServicePolicy(),
      );
      // New instance should be created (not the old cached one)
      expect(identical(storeBefore, storeAfter), isFalse);
    });

    test('unregister removes store from registry', () {
      ProviderTileCacheManager.setBaseCacheDir(tempDir.path);

      final store1 = ProviderTileCacheManager.getOrCreate(
        providerId: 'osm',
        tileTypeId: 'street',
        policy: const ServicePolicy(),
      );

      ProviderTileCacheManager.unregister('osm', 'street');

      // Should create a new instance after unregistering
      final store2 = ProviderTileCacheManager.getOrCreate(
        providerId: 'osm',
        tileTypeId: 'street',
        policy: const ServicePolicy(),
      );

      expect(identical(store1, store2), isFalse);
    });
  });

  group('ProviderTileCacheStore eviction', () {
    /// Helper: populate cache with [count] tiles, each [bytesPerTile] bytes.
    /// Uses small delays between writes so modification times are
    /// distinguishable for oldest-modified ordering.
    Future<void> fillCache(
      ProviderTileCacheStore store, {
      required int count,
      required int bytesPerTile,
      String prefix = '',
    }) async {
      final bytes = Uint8List.fromList(List.filled(bytesPerTile, 42));
      final metadata = CachedMapTileMetadata(
        staleAt: DateTime.utc(2026, 3, 1),
        lastModified: null,
        etag: null,
      );
      for (var i = 0; i < count; i++) {
        await store.putTile(
          url: 'https://tile.example.com/$prefix$i.png',
          metadata: metadata,
          bytes: bytes,
        );
        // Small delay so modification times are distinguishable for eviction order
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('eviction reduces cache when exceeding maxCacheBytes', () async {
      final store = ProviderTileCacheStore(
        cacheDirectory: tempDir.path,
        maxCacheBytes: 500,
      );

      // Write tiles that exceed the limit
      await fillCache(store, count: 10, bytesPerTile: 100);

      // Explicitly trigger eviction (bypasses throttle)
      await store.forceEviction();

      final sizeAfter = await store.estimatedSizeBytes;
      expect(sizeAfter, lessThanOrEqualTo(500),
          reason: 'Eviction should reduce cache to at or below limit');
    });

    test('eviction targets 80% of maxCacheBytes', () async {
      final store = ProviderTileCacheStore(
        cacheDirectory: tempDir.path,
        maxCacheBytes: 1000,
      );

      await fillCache(store, count: 10, bytesPerTile: 200);
      await store.forceEviction();

      final sizeAfter = await store.estimatedSizeBytes;
      // Target is 80% of 1000 = 800 bytes
      expect(sizeAfter, lessThanOrEqualTo(800),
          reason: 'Eviction should target 80% of maxCacheBytes');
    });

    test('oldest-modified tiles are evicted first', () async {
      final store = ProviderTileCacheStore(
        cacheDirectory: tempDir.path,
        maxCacheBytes: 500,
      );

      // Write old tiles first (these should be evicted)
      await fillCache(store, count: 5, bytesPerTile: 100, prefix: 'old_');

      // Write newer tiles (these should survive)
      await fillCache(store, count: 5, bytesPerTile: 100, prefix: 'new_');

      await store.forceEviction();

      // Newest tile should still be present
      final newestTile = await store.getTile('https://tile.example.com/new_4.png');
      expect(newestTile, isNotNull,
          reason: 'Newest tiles should survive eviction');

      // Oldest tile should have been evicted
      final oldestTile = await store.getTile('https://tile.example.com/old_0.png');
      expect(oldestTile, isNull,
          reason: 'Oldest tiles should be evicted first');
    });

    test('orphan .meta files are cleaned up during eviction', () async {
      final store = ProviderTileCacheStore(
        cacheDirectory: tempDir.path,
        maxCacheBytes: 500,
      );

      // Write a tile to create the directory
      await fillCache(store, count: 1, bytesPerTile: 50);

      // Manually create an orphan .meta file (no matching .tile)
      final orphanMetaFile = File(p.join(tempDir.path, 'orphan_key.meta'));
      await orphanMetaFile.writeAsString('{"staleAt":0}');
      expect(await orphanMetaFile.exists(), isTrue);

      // Write enough tiles to exceed the limit, then force eviction
      await fillCache(store, count: 10, bytesPerTile: 100, prefix: 'trigger_');
      await store.forceEviction();

      // The orphan .meta file should have been cleaned up
      expect(await orphanMetaFile.exists(), isFalse,
          reason: 'Orphan .meta file should be cleaned up during eviction');
    });

    test('evicted tiles have their .meta files removed too', () async {
      final store = ProviderTileCacheStore(
        cacheDirectory: tempDir.path,
        maxCacheBytes: 300,
      );

      await fillCache(store, count: 10, bytesPerTile: 100);
      await store.forceEviction();

      // After eviction, count remaining .tile and .meta files
      final dir = Directory(tempDir.path);
      final files = await dir.list().toList();
      final tileFiles = files
          .whereType<File>()
          .where((f) => f.path.endsWith('.tile'))
          .length;
      final metaFiles = files
          .whereType<File>()
          .where((f) => f.path.endsWith('.meta'))
          .length;

      // Every remaining .tile should have a matching .meta (1:1)
      expect(metaFiles, equals(tileFiles),
          reason: '.meta count should match .tile count after eviction');
    });

    test('no eviction when cache is under limit', () async {
      final store = ProviderTileCacheStore(
        cacheDirectory: tempDir.path,
        maxCacheBytes: 100000, // 100KB — way more than we'll write
      );

      await fillCache(store, count: 3, bytesPerTile: 50);
      final sizeBefore = await store.estimatedSizeBytes;

      await store.forceEviction();
      final sizeAfter = await store.estimatedSizeBytes;

      expect(sizeAfter, equals(sizeBefore),
          reason: 'No eviction needed when under limit');
    });
  });
}
