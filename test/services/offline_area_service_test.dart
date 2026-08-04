import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:mocktail/mocktail.dart';

import 'package:deflockapp/app_state.dart';
import 'package:deflockapp/services/offline_area_service.dart';
import 'package:deflockapp/services/offline_areas/offline_area_models.dart';

class MockAppState extends Mock implements AppState {}


OfflineArea _makeArea({
  String providerId = 'osm',
  String tileTypeId = 'standard',
  int minZoom = 5,
  int maxZoom = 12,
  OfflineAreaStatus status = OfflineAreaStatus.complete,
}) {
  return OfflineArea(
    id: 'test-$providerId-$tileTypeId-$minZoom-$maxZoom',
    bounds: LatLngBounds(const LatLng(0, 0), const LatLng(1, 1)),
    minZoom: minZoom,
    maxZoom: maxZoom,
    directory: '/tmp/test-area',
    status: status,
    tileProviderId: providerId,
    tileTypeId: tileTypeId,
  );
}

void main() {
  final service = OfflineAreaService();
  late MockAppState mockAppState;

  setUp(() {
    service.setAreasForTesting([]);
    mockAppState = MockAppState();
    AppState.instance = mockAppState;
    // These tests exercise the underlying zoom/provider matching logic, so
    // offline features are enabled by default here — the "disabled" gating
    // itself is covered separately below.
    when(() => mockAppState.offlineFeaturesEnabled).thenReturn(true);
  });


  group('hasOfflineAreasForProviderAtZoom', () {
    test('returns true for zoom within range', () {
      service.setAreasForTesting([_makeArea(minZoom: 5, maxZoom: 12)]);

      expect(service.hasOfflineAreasForProviderAtZoom('osm', 'standard', 5), isTrue);
      expect(service.hasOfflineAreasForProviderAtZoom('osm', 'standard', 8), isTrue);
      expect(service.hasOfflineAreasForProviderAtZoom('osm', 'standard', 12), isTrue);
    });

    test('returns false for zoom outside range', () {
      service.setAreasForTesting([_makeArea(minZoom: 5, maxZoom: 12)]);

      expect(service.hasOfflineAreasForProviderAtZoom('osm', 'standard', 4), isFalse);
      expect(service.hasOfflineAreasForProviderAtZoom('osm', 'standard', 13), isFalse);
      expect(service.hasOfflineAreasForProviderAtZoom('osm', 'standard', 14), isFalse);
    });

    test('returns false for wrong provider', () {
      service.setAreasForTesting([_makeArea(providerId: 'osm')]);

      expect(service.hasOfflineAreasForProviderAtZoom('other', 'standard', 8), isFalse);
    });

    test('returns false for wrong tile type', () {
      service.setAreasForTesting([_makeArea(tileTypeId: 'standard')]);

      expect(service.hasOfflineAreasForProviderAtZoom('osm', 'satellite', 8), isFalse);
    });

    test('returns false for non-complete areas', () {
      service.setAreasForTesting([
        _makeArea(status: OfflineAreaStatus.downloading),
        _makeArea(status: OfflineAreaStatus.error),
      ]);

      expect(service.hasOfflineAreasForProviderAtZoom('osm', 'standard', 8), isFalse);
    });

    test('returns false when initialized with no areas', () {
      service.setAreasForTesting([]);
      expect(service.hasOfflineAreasForProviderAtZoom('osm', 'standard', 8), isFalse);
    });

    test('matches when any area covers the zoom level', () {
      service.setAreasForTesting([
        _makeArea(minZoom: 5, maxZoom: 8),
        _makeArea(minZoom: 10, maxZoom: 14),
      ]);

      // In first area's range
      expect(service.hasOfflineAreasForProviderAtZoom('osm', 'standard', 6), isTrue);
      // In gap between areas
      expect(service.hasOfflineAreasForProviderAtZoom('osm', 'standard', 9), isFalse);
      // In second area's range
      expect(service.hasOfflineAreasForProviderAtZoom('osm', 'standard', 13), isTrue);
      // Beyond both areas
      expect(service.hasOfflineAreasForProviderAtZoom('osm', 'standard', 15), isFalse);
    });
  });

  group('offlineFeaturesEnabled gating', () {
    test('hasOfflineAreasForProvider returns false when feature disabled, even with matching areas', () {
      service.setAreasForTesting([_makeArea(providerId: 'osm', tileTypeId: 'standard')]);
      when(() => mockAppState.offlineFeaturesEnabled).thenReturn(false);

      expect(service.hasOfflineAreasForProvider('osm', 'standard'), isFalse);
    });

    test('hasOfflineAreasForProviderAtZoom returns false when feature disabled, even within zoom range', () {
      service.setAreasForTesting([_makeArea(minZoom: 5, maxZoom: 12)]);
      when(() => mockAppState.offlineFeaturesEnabled).thenReturn(false);

      expect(service.hasOfflineAreasForProviderAtZoom('osm', 'standard', 8), isFalse);
    });

    test('re-enabling offlineFeaturesEnabled restores normal matching', () {
      service.setAreasForTesting([_makeArea(minZoom: 5, maxZoom: 12)]);
      when(() => mockAppState.offlineFeaturesEnabled).thenReturn(false);
      expect(service.hasOfflineAreasForProviderAtZoom('osm', 'standard', 8), isFalse);

      when(() => mockAppState.offlineFeaturesEnabled).thenReturn(true);
      expect(service.hasOfflineAreasForProviderAtZoom('osm', 'standard', 8), isTrue);
    });
  });
}

