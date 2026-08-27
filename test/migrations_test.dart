import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deflockapp/app_state.dart';
import 'package:deflockapp/migrations.dart';
import 'package:deflockapp/models/node_profile.dart';
import 'package:deflockapp/models/pending_upload.dart';
import 'package:deflockapp/services/profile_service.dart';
import 'package:deflockapp/state/settings_state.dart';
import 'package:deflockapp/state/upload_queue_state.dart';

class MockAppState extends Mock implements AppState {}

NodeProfile staleFlockRavenProfile() => NodeProfile(
      id: 'builtin-flock-raven',
      name: 'Flock Raven',
      tags: const {
        'man_made': 'surveillance',
        'surveillance': 'public',
        'surveillance:type': 'gunshot_detector',
        'brand': 'Flock Safety',
        'brand:wikidata': 'Q108485435',
      },
      builtin: true,
      requiresDirection: false,
    );

void main() {
  late MockAppState mockAppState;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockAppState = MockAppState();
    AppState.instance = mockAppState;
    when(() => mockAppState.offlineMode).thenReturn(false);
    when(() => mockAppState.offlineFeaturesEnabled).thenReturn(false);
    when(() => mockAppState.reloadProfiles()).thenAnswer((_) async {});
    when(() => mockAppState.migrateFlockRavenQueueTags()).thenAnswer((_) async => false);
  });

  group('OneTimeMigrations.migrate_2_11_1 (profile catalog)', () {
    test('fixes stale Flock Raven profile tags in storage', () async {
      await ProfileService().save([staleFlockRavenProfile()]);

      await OneTimeMigrations.migrate_2_11_1(mockAppState);

      final saved = await ProfileService().load();
      final fixed = saved.firstWhere((p) => p.id == 'builtin-flock-raven');

      expect(fixed.tags['surveillance'], 'outdoor');
      expect(fixed.tags['manufacturer'], 'Flock Safety');
      expect(fixed.tags['manufacturer:wikidata'], 'Q108485435');
      expect(fixed.tags.containsKey('brand'), isFalse);
      expect(fixed.tags.containsKey('brand:wikidata'), isFalse);

      verify(() => mockAppState.reloadProfiles()).called(1);
      verify(() => mockAppState.migrateFlockRavenQueueTags()).called(1);
    });

    test('leaves an already-correct profile untouched', () async {
      final correctProfile = staleFlockRavenProfile().copyWith(tags: const {
        'man_made': 'surveillance',
        'surveillance': 'outdoor',
        'surveillance:type': 'gunshot_detector',
        'manufacturer': 'Flock Safety',
        'manufacturer:wikidata': 'Q108485435',
      });
      await ProfileService().save([correctProfile]);

      await OneTimeMigrations.migrate_2_11_1(mockAppState);

      verifyNever(() => mockAppState.reloadProfiles());
    });

    test('does not touch the unrelated ALPR "Flock" profile', () async {
      final alprFlock = NodeProfile(
        id: 'builtin-flock',
        name: 'Flock',
        tags: const {
          'man_made': 'surveillance',
          'surveillance': 'public',
          'surveillance:type': 'ALPR',
          'manufacturer': 'Flock Safety',
          'manufacturer:wikidata': 'Q108485435',
        },
        builtin: true,
      );
      await ProfileService().save([alprFlock]);

      await OneTimeMigrations.migrate_2_11_1(mockAppState);

      final saved = await ProfileService().load();
      expect(saved.single.tags, alprFlock.tags);
      verifyNever(() => mockAppState.reloadProfiles());
    });
  });

  group('UploadQueueState.migrateFlockRavenQueueTags', () {
    test('fixes a queued (not-yet-uploaded) Flock Raven entry', () async {
      final pending = PendingUpload(
        coord: const LatLng(1, 2),
        direction: 0,
        profile: staleFlockRavenProfile(),
        changesetComment: 'Add Flock Raven surveillance node',
        uploadMode: UploadMode.simulate,
        operation: UploadOperation.create,
      );

      SharedPreferences.setMockInitialValues({
        'queue': jsonEncode([pending.toJson()]),
      });

      final state = UploadQueueState();
      await state.init();

      final changed = await state.migrateFlockRavenQueueTags();
      expect(changed, isTrue);

      final fixedTags = state.pendingUploads.single.profile!.tags;
      expect(fixedTags['surveillance'], 'outdoor');
      expect(fixedTags['manufacturer'], 'Flock Safety');
      expect(fixedTags.containsKey('brand'), isFalse);

      // Persisted change should survive a reload.
      final reloaded = UploadQueueState();
      await reloaded.init();
      expect(reloaded.pendingUploads.single.profile!.tags['surveillance'], 'outdoor');
    });

    test('leaves a queue with no Flock Raven entries unchanged', () async {
      SharedPreferences.setMockInitialValues({'queue': jsonEncode([])});

      final state = UploadQueueState();
      await state.init();

      final changed = await state.migrateFlockRavenQueueTags();
      expect(changed, isFalse);
    });
  });
}
