import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:deflockapp/models/node_profile.dart';
import 'package:deflockapp/models/osm_node.dart';
import 'package:deflockapp/state/profile_state.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('NodeProfile', () {
    test('toJson/fromJson round-trip preserves all fields', () {
      final profile = NodeProfile(
        id: 'test-id',
        name: 'Test Profile',
        tags: const {'man_made': 'surveillance', 'camera:type': 'fixed'},
        builtin: true,
        requiresDirection: false,
        submittable: true,
        editable: false,
        fov: 90.0,
      );

      final json = profile.toJson();
      final restored = NodeProfile.fromJson(json);

      expect(restored.id, equals(profile.id));
      expect(restored.name, equals(profile.name));
      expect(restored.tags, equals(profile.tags));
      expect(restored.builtin, equals(profile.builtin));
      expect(restored.requiresDirection, equals(profile.requiresDirection));
      expect(restored.submittable, equals(profile.submittable));
      expect(restored.editable, equals(profile.editable));
      expect(restored.fov, equals(profile.fov));
    });

    test('getDefaults returns expected profiles', () {
      final defaults = NodeProfile.getDefaults();

      expect(defaults.length, greaterThanOrEqualTo(10));

      final ids = defaults.map((p) => p.id).toSet();
      expect(ids, contains('builtin-flock'));
      expect(ids, contains('builtin-generic-alpr'));
      expect(ids, contains('builtin-motorola'));
      expect(ids, contains('builtin-shotspotter'));
    });

    test('empty tag values exist in default profiles', () {
      // Documents that profiles like builtin-flock ship with camera:mount: ''
      // This is the root cause of the HTTP 400 bug — the routing service must
      // filter these out before sending to the API.
      final defaults = NodeProfile.getDefaults();
      final flock = defaults.firstWhere((p) => p.id == 'builtin-flock');

      expect(flock.tags.containsKey('camera:mount'), isTrue);
      expect(flock.tags['camera:mount'], equals(''));
    });

    test('equality is based on id', () {
      final a = NodeProfile(
        id: 'same-id',
        name: 'Profile A',
        tags: const {'tag': 'a'},
      );
      final b = NodeProfile(
        id: 'same-id',
        name: 'Profile B',
        tags: const {'tag': 'b'},
      );
      final c = NodeProfile(
        id: 'different-id',
        name: 'Profile A',
        tags: const {'tag': 'a'},
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    group('createExistingTagsProfile', () {
      test('should NOT assign FOV for nodes with single direction', () {
        // This is the core bug fix: nodes with just "direction=90" should not get a default FOV
        final node = OsmNode(
          id: 123,
          coord: const LatLng(37.7749, -122.4194),
          tags: {
            'direction': '90',
            'man_made': 'surveillance',
            'surveillance:type': 'ALPR',
          },
        );

        final profile = NodeProfile.createExistingTagsProfile(node);

        expect(profile.fov, isNull, reason: 'Single direction nodes should not get default FOV');
        expect(profile.name, equals('<Existing tags>'));
        expect(profile.tags, isEmpty, reason: 'Existing tags profile should have empty tags');
      });

      test('should assign FOV for nodes with range notation', () {
        final node = OsmNode(
          id: 123,
          coord: const LatLng(37.7749, -122.4194),
          tags: {
            'direction': '55-125', // Range notation = explicit FOV
            'man_made': 'surveillance',
            'surveillance:type': 'ALPR',
          },
        );

        final profile = NodeProfile.createExistingTagsProfile(node);

        expect(profile.fov, isNotNull, reason: 'Range notation should preserve FOV');
        expect(profile.fov, equals(70.0), reason: 'Range 55-125 should calculate to 70 degree FOV');
      });

      test('should assign FOV for nodes with multiple consistent ranges', () {
        final node = OsmNode(
          id: 123,
          coord: const LatLng(37.7749, -122.4194),
          tags: {
            'direction': '55-125;235-305', // Two ranges with same FOV
            'man_made': 'surveillance',
            'surveillance:type': 'ALPR',
          },
        );

        final profile = NodeProfile.createExistingTagsProfile(node);

        expect(profile.fov, equals(70.0), reason: 'Multiple consistent ranges should preserve FOV');
      });

      test('should NOT assign FOV for mixed single directions and ranges', () {
        final node = OsmNode(
          id: 123,
          coord: const LatLng(37.7749, -122.4194),
          tags: {
            'direction': '90;180-360', // Mix of single direction and range
            'man_made': 'surveillance',
            'surveillance:type': 'ALPR',
          },
        );

        final profile = NodeProfile.createExistingTagsProfile(node);

        expect(profile.fov, isNull, reason: 'Mixed notation should not assign FOV');
      });

      test('should NOT assign FOV for multiple single directions', () {
        final node = OsmNode(
          id: 123,
          coord: const LatLng(37.7749, -122.4194),
          tags: {
            'direction': '90;180;270', // Multiple single directions
            'man_made': 'surveillance',
            'surveillance:type': 'ALPR',
          },
        );

        final profile = NodeProfile.createExistingTagsProfile(node);

        expect(profile.fov, isNull, reason: 'Multiple single directions should not get default FOV');
      });

      test('should handle camera:direction tag', () {
        final node = OsmNode(
          id: 123,
          coord: const LatLng(37.7749, -122.4194),
          tags: {
            'camera:direction': '180', // Using camera:direction instead of direction
            'man_made': 'surveillance',
            'surveillance:type': 'camera',
          },
        );

        final profile = NodeProfile.createExistingTagsProfile(node);

        expect(profile.fov, isNull, reason: 'Single camera:direction should not get default FOV');
      });

      test('should fix the specific bug: direction=90 should not become direction=55-125', () {
        // This tests the exact bug scenario mentioned in the issue
        final node = OsmNode(
          id: 123,
          coord: const LatLng(37.7749, -122.4194),
          tags: {
            'direction': '90', // Single direction, should stay as single direction
            'man_made': 'surveillance',
            'surveillance:type': 'ALPR',
          },
        );

        final profile = NodeProfile.createExistingTagsProfile(node);

        // Key fix: profile should NOT have an FOV, so upload won't convert to range notation
        expect(profile.fov, isNull, reason: 'direction=90 should not get converted to direction=55-125');
        
        // Verify the node does have directionFovPairs (for rendering), but profile ignores them
        expect(node.directionFovPairs, hasLength(1));
        expect(node.directionFovPairs.first.centerDegrees, equals(90.0));
        expect(node.directionFovPairs.first.fovDegrees, equals(70.0)); // Default FOV for rendering
      });
    });

    group('ProfileState reordering', () {
      test('should reorder profiles correctly', () async {
        final profileState = ProfileState();
        
        // Add some test profiles directly to avoid storage operations
        final profileA = NodeProfile(id: 'a', name: 'Profile A', tags: const {});
        final profileB = NodeProfile(id: 'b', name: 'Profile B', tags: const {});
        final profileC = NodeProfile(id: 'c', name: 'Profile C', tags: const {});
        
        // Add profiles directly to the internal list to avoid storage
        profileState.internalProfiles.addAll([profileA, profileB, profileC]);
        profileState.internalEnabled.addAll([profileA, profileB, profileC]);
        
        // Initial order should be A, B, C
        expect(profileState.profiles.map((p) => p.id), equals(['a', 'b', 'c']));
        
        // Move profile at index 0 (A) to index 2 (should become B, A, C due to Flutter's reorder logic)
        profileState.reorderProfiles(0, 2);
        expect(profileState.profiles.map((p) => p.id), equals(['b', 'a', 'c']));
        
        // Move profile at index 1 (A) to index 0 (should become A, B, C)
        profileState.reorderProfiles(1, 0);
        expect(profileState.profiles.map((p) => p.id), equals(['a', 'b', 'c']));
      });

      test('should maintain enabled status after reordering', () {
        final profileState = ProfileState();
        
        final profileA = NodeProfile(id: 'a', name: 'Profile A', tags: const {});
        final profileB = NodeProfile(id: 'b', name: 'Profile B', tags: const {});
        final profileC = NodeProfile(id: 'c', name: 'Profile C', tags: const {});
        
        // Add profiles directly to avoid storage operations
        profileState.internalProfiles.addAll([profileA, profileB, profileC]);
        profileState.internalEnabled.addAll([profileA, profileB, profileC]);
        
        // Disable profile B
        profileState.internalEnabled.remove(profileB);
        expect(profileState.isEnabled(profileB), isFalse);
        
        // Reorder profiles
        profileState.reorderProfiles(0, 2);
        
        // Profile B should still be disabled after reordering
        expect(profileState.isEnabled(profileB), isFalse);
        expect(profileState.isEnabled(profileA), isTrue);
        expect(profileState.isEnabled(profileC), isTrue);
      });
    });
  });
}
