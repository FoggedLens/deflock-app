import 'package:deflockapp/models/node_profile.dart';
import 'package:deflockapp/models/osm_node.dart';
import 'package:deflockapp/services/edit_node_change_detector.dart';
import 'package:deflockapp/state/session_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('EditNodeChangeDetector direction serialization', () {
    test(
      'detects changing a range direction to a single direction with the same center',
      () {
        final session = _sessionFor(
          originalDirection: '55-125',
          profileFov: null,
        );

        expect(
          EditNodeChangeDetector.hasActualChanges(session),
          isTrue,
          reason: 'direction=55-125 serializes differently from direction=90',
        );
      },
    );

    test('treats an unchanged range direction as unchanged', () {
      final session = _sessionFor(originalDirection: '55-125', profileFov: 70);

      expect(EditNodeChangeDetector.hasActualChanges(session), isFalse);
    });

    test('treats an unchanged single direction as unchanged', () {
      final session = _sessionFor(originalDirection: '90', profileFov: null);

      expect(EditNodeChangeDetector.hasActualChanges(session), isFalse);
    });

    test('treats an unchanged directionless node as unchanged', () {
      final session = _sessionFor(originalDirection: null, profileFov: null)
        ..directions = <double>[]
        ..currentDirectionIndex = -1;

      expect(EditNodeChangeDetector.hasActualChanges(session), isFalse);
    });
  });
}

EditNodeSession _sessionFor({
  required String? originalDirection,
  required double? profileFov,
}) {
  const coord = LatLng(37.7749, -122.4194);
  final node = OsmNode(
    id: 157,
    coord: coord,
    tags: {'man_made': 'surveillance', 'direction': ?originalDirection},
  );
  final profile = NodeProfile(
    id: 'existing-tags-157',
    name: 'Existing tags',
    tags: const {},
    fov: profileFov,
  );

  return EditNodeSession(
    originalNode: node,
    originalHadDirections: originalDirection != null,
    profile: profile,
    initialDirection: 90,
    target: coord,
    additionalExistingTags: const {'man_made': 'surveillance'},
  );
}
