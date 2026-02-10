import 'package:flutter_test/flutter_test.dart';
import 'package:deflockapp/models/node_profile.dart';

void main() {
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
  });
}
