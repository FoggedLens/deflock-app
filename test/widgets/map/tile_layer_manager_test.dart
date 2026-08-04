import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deflockapp/models/tile_provider.dart' as models;
import 'package:deflockapp/services/deflock_tile_provider.dart';
import 'package:deflockapp/widgets/map/tile_layer_manager.dart';

class MockTileImage extends Mock implements TileImage {}

void main() {
  group('TileLayerManager exponential backoff', () {
    test('initial retry delay is 2 seconds', () {
      final manager = TileLayerManager();
      expect(manager.retryDelay, equals(const Duration(seconds: 2)));
      manager.dispose();
    });

    test('scheduleRetry fires reset stream after delay', () {
      FakeAsync().run((async) {
        final manager = TileLayerManager();
        final resets = <void>[];
        manager.resetStream.listen((_) => resets.add(null));

        manager.scheduleRetry();

        expect(resets, isEmpty);
        async.elapse(const Duration(seconds: 1));
        expect(resets, isEmpty);
        async.elapse(const Duration(seconds: 1));
        expect(resets, hasLength(1));

        manager.dispose();
      });
    });

    test('delay doubles after each retry fires', () {
      FakeAsync().run((async) {
        final manager = TileLayerManager();
        manager.resetStream.listen((_) {});

        // First retry: 2s
        manager.scheduleRetry();
        async.elapse(const Duration(seconds: 2));
        expect(manager.retryDelay, equals(const Duration(seconds: 4)));

        // Second retry: 4s
        manager.scheduleRetry();
        async.elapse(const Duration(seconds: 4));
        expect(manager.retryDelay, equals(const Duration(seconds: 8)));

        // Third retry: 8s
        manager.scheduleRetry();
        async.elapse(const Duration(seconds: 8));
        expect(manager.retryDelay, equals(const Duration(seconds: 16)));

        manager.dispose();
      });
    });

    test('delay caps at 60 seconds', () {
      FakeAsync().run((async) {
        final manager = TileLayerManager();
        manager.resetStream.listen((_) {});

        // Drive through cycles: 2 → 4 → 8 → 16 → 32 → 60 → 60
        var currentDelay = manager.retryDelay;
        while (currentDelay < const Duration(seconds: 60)) {
          manager.scheduleRetry();
          async.elapse(currentDelay);
          currentDelay = manager.retryDelay;
        }

        // Should be capped at 60s
        expect(manager.retryDelay, equals(const Duration(seconds: 60)));

        // Another cycle stays at 60s
        manager.scheduleRetry();
        async.elapse(const Duration(seconds: 60));
        expect(manager.retryDelay, equals(const Duration(seconds: 60)));

        manager.dispose();
      });
    });

    test('onTileLoadSuccess resets delay to minimum', () {
      FakeAsync().run((async) {
        final manager = TileLayerManager();
        manager.resetStream.listen((_) {});

        // Drive up the delay
        manager.scheduleRetry();
        async.elapse(const Duration(seconds: 2));
        expect(manager.retryDelay, equals(const Duration(seconds: 4)));

        manager.scheduleRetry();
        async.elapse(const Duration(seconds: 4));
        expect(manager.retryDelay, equals(const Duration(seconds: 8)));

        // Reset on success
        manager.onTileLoadSuccess();
        expect(manager.retryDelay, equals(const Duration(seconds: 2)));

        manager.dispose();
      });
    });

    test('rapid errors debounce: only last timer fires', () {
      FakeAsync().run((async) {
        final manager = TileLayerManager();
        final resets = <void>[];
        manager.resetStream.listen((_) => resets.add(null));

        // Fire 3 errors in quick succession (each cancels the previous timer)
        manager.scheduleRetry();
        async.elapse(const Duration(milliseconds: 500));
        manager.scheduleRetry();
        async.elapse(const Duration(milliseconds: 500));
        manager.scheduleRetry();

        // 1s elapsed total since first error, but last timer started 0ms ago
        // Need to wait 2s from *last* scheduleRetry call
        async.elapse(const Duration(seconds: 1));
        expect(resets, isEmpty, reason: 'Timer should not fire yet');
        async.elapse(const Duration(seconds: 1));
        expect(resets, hasLength(1), reason: 'Only one reset should fire');

        manager.dispose();
      });
    });

    test('delay stays at minimum if no retries have fired', () {
      final manager = TileLayerManager();
      // Just calling onTileLoadSuccess without any errors
      manager.onTileLoadSuccess();
      expect(manager.retryDelay, equals(const Duration(seconds: 2)));
      manager.dispose();
    });

    test('backoff progression: 2 → 4 → 8 → 16 → 32 → 60 → 60', () {
      FakeAsync().run((async) {
        final manager = TileLayerManager();
        manager.resetStream.listen((_) {});

        final expectedDelays = [
          const Duration(seconds: 2),
          const Duration(seconds: 4),
          const Duration(seconds: 8),
          const Duration(seconds: 16),
          const Duration(seconds: 32),
          const Duration(seconds: 60),
          const Duration(seconds: 60), // capped
        ];

        for (var i = 0; i < expectedDelays.length; i++) {
          expect(manager.retryDelay, equals(expectedDelays[i]),
              reason: 'Step $i');
          manager.scheduleRetry();
          async.elapse(expectedDelays[i]);
        }

        manager.dispose();
      });
    });

    test('dispose cancels pending retry timer', () {
      FakeAsync().run((async) {
        final manager = TileLayerManager();
        final resets = <void>[];
        late StreamSubscription<void> sub;
        sub = manager.resetStream.listen((_) => resets.add(null));

        manager.scheduleRetry();
        // Dispose before timer fires
        sub.cancel();
        manager.dispose();

        async.elapse(const Duration(seconds: 10));
        expect(resets, isEmpty, reason: 'Timer should be cancelled by dispose');
      });
    });
  });

  group('TileLayerManager checkAndClearCacheIfNeeded', () {
    late TileLayerManager manager;

    setUp(() {
      manager = TileLayerManager();
    });

    tearDown(() {
      manager.dispose();
    });

    test('first call triggers clear (initial null differs from provided values)', () {
      final result = manager.checkAndClearCacheIfNeeded(
        currentProviderId: 'osm',
        currentTileTypeId: 'street',
        currentOfflineMode: false,
      );
      // First call: internal state is (null, null, false) → (osm, street, false)
      // provider null→osm triggers clear. Harmless: no tiles to clear yet.
      expect(result, isTrue);
    });

    test('same values on second call returns false', () {
      manager.checkAndClearCacheIfNeeded(
        currentProviderId: 'osm',
        currentTileTypeId: 'street',
        currentOfflineMode: false,
      );
      final result = manager.checkAndClearCacheIfNeeded(
        currentProviderId: 'osm',
        currentTileTypeId: 'street',
        currentOfflineMode: false,
      );
      expect(result, isFalse);
    });

    test('different provider triggers cache clear', () {
      manager.checkAndClearCacheIfNeeded(
        currentProviderId: 'osm',
        currentTileTypeId: 'street',
        currentOfflineMode: false,
      );
      final result = manager.checkAndClearCacheIfNeeded(
        currentProviderId: 'bing',
        currentTileTypeId: 'street',
        currentOfflineMode: false,
      );
      expect(result, isTrue);
    });

    test('different tile type triggers cache clear', () {
      manager.checkAndClearCacheIfNeeded(
        currentProviderId: 'osm',
        currentTileTypeId: 'street',
        currentOfflineMode: false,
      );
      final result = manager.checkAndClearCacheIfNeeded(
        currentProviderId: 'osm',
        currentTileTypeId: 'satellite',
        currentOfflineMode: false,
      );
      expect(result, isTrue);
    });

    test('different offline mode triggers cache clear', () {
      manager.checkAndClearCacheIfNeeded(
        currentProviderId: 'osm',
        currentTileTypeId: 'street',
        currentOfflineMode: false,
      );
      final result = manager.checkAndClearCacheIfNeeded(
        currentProviderId: 'osm',
        currentTileTypeId: 'street',
        currentOfflineMode: true,
      );
      expect(result, isTrue);
    });

    test('cache clear increments mapRebuildKey', () {
      final initialKey = manager.mapRebuildKey;
      manager.checkAndClearCacheIfNeeded(
        currentProviderId: 'osm',
        currentTileTypeId: 'street',
        currentOfflineMode: false,
      );
      // First call increments (null → osm)
      expect(manager.mapRebuildKey, equals(initialKey + 1));

      manager.checkAndClearCacheIfNeeded(
        currentProviderId: 'osm',
        currentTileTypeId: 'satellite',
        currentOfflineMode: false,
      );
      // Type change should increment again
      expect(manager.mapRebuildKey, equals(initialKey + 2));
    });

    test('no cache clear does not increment mapRebuildKey', () {
      manager.checkAndClearCacheIfNeeded(
        currentProviderId: 'osm',
        currentTileTypeId: 'street',
        currentOfflineMode: false,
      );
      final keyAfterFirst = manager.mapRebuildKey;

      manager.checkAndClearCacheIfNeeded(
        currentProviderId: 'osm',
        currentTileTypeId: 'street',
        currentOfflineMode: false,
      );
      expect(manager.mapRebuildKey, equals(keyAfterFirst));
    });

    test('null to non-null transition triggers clear', () {
      manager.checkAndClearCacheIfNeeded(
        currentProviderId: null,
        currentTileTypeId: null,
        currentOfflineMode: false,
      );
      final result = manager.checkAndClearCacheIfNeeded(
        currentProviderId: 'osm',
        currentTileTypeId: 'street',
        currentOfflineMode: false,
      );
      // null → osm is a change — triggers clear so stale tiles are flushed
      expect(result, isTrue);
    });

    test('non-null to null to non-null triggers clear both times', () {
      manager.checkAndClearCacheIfNeeded(
        currentProviderId: 'osm',
        currentTileTypeId: 'street',
        currentOfflineMode: false,
      );

      // Provider goes null (e.g., during reload)
      expect(
        manager.checkAndClearCacheIfNeeded(
          currentProviderId: null,
          currentTileTypeId: null,
          currentOfflineMode: false,
        ),
        isTrue,
      );

      // Provider returns — should still trigger clear
      expect(
        manager.checkAndClearCacheIfNeeded(
          currentProviderId: 'bing',
          currentTileTypeId: 'street',
          currentOfflineMode: false,
        ),
        isTrue,
      );
    });

    test('switching back and forth triggers clear each time', () {
      manager.checkAndClearCacheIfNeeded(
        currentProviderId: 'osm',
        currentTileTypeId: 'street',
        currentOfflineMode: false,
      );

      expect(
        manager.checkAndClearCacheIfNeeded(
          currentProviderId: 'osm',
          currentTileTypeId: 'satellite',
          currentOfflineMode: false,
        ),
        isTrue,
      );

      expect(
        manager.checkAndClearCacheIfNeeded(
          currentProviderId: 'osm',
          currentTileTypeId: 'street',
          currentOfflineMode: false,
        ),
        isTrue,
      );
    });

    test('switching providers with same tile type triggers clear', () {
      manager.checkAndClearCacheIfNeeded(
        currentProviderId: 'osm',
        currentTileTypeId: 'standard',
        currentOfflineMode: false,
      );

      final result = manager.checkAndClearCacheIfNeeded(
        currentProviderId: 'bing',
        currentTileTypeId: 'standard',
        currentOfflineMode: false,
      );
      expect(result, isTrue);
    });

    test('provider switch resets retry delay and cancels pending timer', () {
      FakeAsync().run((async) {
        final resets = <void>[];
        manager.resetStream.listen((_) => resets.add(null));

        // Escalate backoff: 2s → 4s → 8s
        manager.scheduleRetry();
        async.elapse(const Duration(seconds: 2));
        manager.scheduleRetry();
        async.elapse(const Duration(seconds: 4));
        expect(manager.retryDelay, equals(const Duration(seconds: 8)));

        // Start another retry timer (hasn't fired yet)
        manager.scheduleRetry();

        // Switch provider — should reset delay and cancel pending timer
        manager.checkAndClearCacheIfNeeded(
          currentProviderId: 'osm',
          currentTileTypeId: 'street',
          currentOfflineMode: false,
        );
        manager.checkAndClearCacheIfNeeded(
          currentProviderId: 'bing',
          currentTileTypeId: 'street',
          currentOfflineMode: false,
        );

        expect(manager.retryDelay, equals(const Duration(seconds: 2)));

        // The pending 8s timer should have been cancelled
        final resetsBefore = resets.length;
        async.elapse(const Duration(seconds: 10));
        expect(resets.length, equals(resetsBefore),
            reason: 'Old retry timer should be cancelled on provider switch');
      });
    });
  });

  group('TileLayerManager config drift detection', () {
    late TileLayerManager manager;

    setUp(() {
      manager = TileLayerManager();
    });

    tearDown(() {
      manager.dispose();
    });

    models.TileProvider makeProvider({String? apiKey}) => models.TileProvider(
          id: 'test_provider',
          name: 'Test',
          apiKey: apiKey,
          tileTypes: [],
        );

    models.TileType makeTileType({
      String urlTemplate = 'https://example.com/{z}/{x}/{y}.png',
      int maxZoom = 18,
    }) =>
        models.TileType(
          id: 'test_tile',
          name: 'Test',
          urlTemplate: urlTemplate,
          attribution: 'Test',
          maxZoom: maxZoom,
        );

    test('returns same provider for identical config', () {
      final provider = makeProvider();
      final tileType = makeTileType();

      final layer1 = manager.buildTileLayer(
        selectedProvider: provider,
        selectedTileType: tileType,
      ) as TileLayer;

      final layer2 = manager.buildTileLayer(
        selectedProvider: provider,
        selectedTileType: tileType,
      ) as TileLayer;

      expect(
        identical(layer1.tileProvider, layer2.tileProvider),
        isTrue,
        reason: 'Same config should return the cached provider instance',
      );
    });

    test('replaces provider when urlTemplate changes', () {
      final provider = makeProvider();
      final tileTypeV1 = makeTileType(
        urlTemplate: 'https://old.example.com/{z}/{x}/{y}.png',
      );
      final tileTypeV2 = makeTileType(
        urlTemplate: 'https://new.example.com/{z}/{x}/{y}.png',
      );

      final layer1 = manager.buildTileLayer(
        selectedProvider: provider,
        selectedTileType: tileTypeV1,
      ) as TileLayer;

      final layer2 = manager.buildTileLayer(
        selectedProvider: provider,
        selectedTileType: tileTypeV2,
      ) as TileLayer;

      expect(
        identical(layer1.tileProvider, layer2.tileProvider),
        isFalse,
        reason: 'Changed urlTemplate should create a new provider',
      );
      expect(
        (layer2.tileProvider as DeflockTileProvider).tileType.urlTemplate,
        'https://new.example.com/{z}/{x}/{y}.png',
      );
    });

    test('replaces provider when apiKey changes', () {
      final providerV1 = makeProvider(apiKey: 'old_key');
      final providerV2 = makeProvider(apiKey: 'new_key');
      final tileType = makeTileType();

      final layer1 = manager.buildTileLayer(
        selectedProvider: providerV1,
        selectedTileType: tileType,
      ) as TileLayer;

      final layer2 = manager.buildTileLayer(
        selectedProvider: providerV2,
        selectedTileType: tileType,
      ) as TileLayer;

      expect(
        identical(layer1.tileProvider, layer2.tileProvider),
        isFalse,
        reason: 'Changed apiKey should create a new provider',
      );
      expect(
        (layer2.tileProvider as DeflockTileProvider).apiKey,
        'new_key',
      );
    });

    test('replaces provider when maxZoom changes', () {
      final provider = makeProvider();
      final tileTypeV1 = makeTileType(maxZoom: 18);
      final tileTypeV2 = makeTileType(maxZoom: 20);

      final layer1 = manager.buildTileLayer(
        selectedProvider: provider,
        selectedTileType: tileTypeV1,
      ) as TileLayer;

      final layer2 = manager.buildTileLayer(
        selectedProvider: provider,
        selectedTileType: tileTypeV2,
      ) as TileLayer;

      expect(
        identical(layer1.tileProvider, layer2.tileProvider),
        isFalse,
        reason: 'Changed maxZoom should create a new provider',
      );
    });
  });

  group('TileLayerManager error-type filtering', () {
    late TileLayerManager manager;
    late MockTileImage mockTile;

    setUp(() {
      manager = TileLayerManager();
      mockTile = MockTileImage();
      when(() => mockTile.coordinates)
          .thenReturn(const TileCoordinates(1, 2, 3));
    });

    tearDown(() {
      manager.dispose();
    });

    test('skips retry for TileLoadCancelledException', () {
      FakeAsync().run((async) {
        final resets = <void>[];
        manager.resetStream.listen((_) => resets.add(null));

        manager.onTileLoadError(
          mockTile,
          const TileLoadCancelledException(),
          null,
        );

        // Even after waiting well past the retry delay, no reset should fire.
        async.elapse(const Duration(seconds: 10));
        expect(resets, isEmpty);
      });
    });

    test('skips retry for TileNotAvailableOfflineException', () {
      FakeAsync().run((async) {
        final resets = <void>[];
        manager.resetStream.listen((_) => resets.add(null));

        manager.onTileLoadError(
          mockTile,
          const TileNotAvailableOfflineException(),
          null,
        );

        async.elapse(const Duration(seconds: 10));
        expect(resets, isEmpty);
      });
    });

    test('schedules retry for other errors (e.g. HttpException)', () {
      FakeAsync().run((async) {
        final resets = <void>[];
        manager.resetStream.listen((_) => resets.add(null));

        manager.onTileLoadError(
          mockTile,
          const HttpException('tile fetch failed'),
          null,
        );

        // Should fire after the initial 2s retry delay.
        async.elapse(const Duration(seconds: 2));
        expect(resets, hasLength(1));
      });
    });
  });
}
