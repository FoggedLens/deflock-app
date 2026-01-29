import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:deflockapp/models/osm_node.dart';

void main() {
  group('OsmNode Direction Parsing', () {
    test('should parse 360-degree FOV from X-X notation', () {
      final node = OsmNode(
        id: 1,
        coord: const LatLng(0, 0),
        tags: {'direction': '180-180'},
      );

      final directionFovPairs = node.directionFovPairs;
      
      expect(directionFovPairs, hasLength(1));
      expect(directionFovPairs[0].centerDegrees, equals(180.0));
      expect(directionFovPairs[0].fovDegrees, equals(360.0));
    });

    test('should parse 360-degree FOV from 0-0 notation', () {
      final node = OsmNode(
        id: 1,
        coord: const LatLng(0, 0),
        tags: {'direction': '0-0'},
      );

      final directionFovPairs = node.directionFovPairs;
      
      expect(directionFovPairs, hasLength(1));
      expect(directionFovPairs[0].centerDegrees, equals(0.0));
      expect(directionFovPairs[0].fovDegrees, equals(360.0));
    });

    test('should parse 360-degree FOV from 270-270 notation', () {
      final node = OsmNode(
        id: 1,
        coord: const LatLng(0, 0),
        tags: {'direction': '270-270'},
      );

      final directionFovPairs = node.directionFovPairs;
      
      expect(directionFovPairs, hasLength(1));
      expect(directionFovPairs[0].centerDegrees, equals(270.0));
      expect(directionFovPairs[0].fovDegrees, equals(360.0));
    });

    test('should parse normal range notation correctly', () {
      final node = OsmNode(
        id: 1,
        coord: const LatLng(0, 0),
        tags: {'direction': '90-270'},
      );

      final directionFovPairs = node.directionFovPairs;
      
      expect(directionFovPairs, hasLength(1));
      expect(directionFovPairs[0].centerDegrees, equals(180.0));
      expect(directionFovPairs[0].fovDegrees, equals(180.0));
    });

    test('should parse wrapping range notation correctly', () {
      final node = OsmNode(
        id: 1,
        coord: const LatLng(0, 0),
        tags: {'direction': '270-90'},
      );

      final directionFovPairs = node.directionFovPairs;
      
      expect(directionFovPairs, hasLength(1));
      expect(directionFovPairs[0].centerDegrees, equals(0.0));
      expect(directionFovPairs[0].fovDegrees, equals(180.0));
    });

    test('should parse single direction correctly', () {
      final node = OsmNode(
        id: 1,
        coord: const LatLng(0, 0),
        tags: {'direction': '90'},
      );

      final directionFovPairs = node.directionFovPairs;
      
      expect(directionFovPairs, hasLength(1));
      expect(directionFovPairs[0].centerDegrees, equals(90.0));
      // Default FOV from dev_config (kDirectionConeHalfAngle * 2)
    });
  });
}