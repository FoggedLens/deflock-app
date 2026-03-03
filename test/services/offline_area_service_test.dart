import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;

import 'package:deflockapp/services/offline_area_service.dart';
import 'package:deflockapp/services/offline_areas/offline_area_models.dart';

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

  setUp(() {
    service.setAreasForTesting([]);
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
}
