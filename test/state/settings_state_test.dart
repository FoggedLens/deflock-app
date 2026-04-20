import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deflockapp/models/service_endpoint.dart';
import 'package:deflockapp/state/settings_state.dart';
import 'package:deflockapp/keys.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('kHasOsmSecrets (no --dart-define)', () {
    test('is false when built without secrets', () {
      expect(kHasOsmSecrets, isFalse);
    });

    test('client ID getters return empty strings instead of throwing', () {
      expect(kOsmProdClientId, isEmpty);
      expect(kOsmSandboxClientId, isEmpty);
    });
  });

  group('SettingsState without secrets', () {
    test('defaults to simulate mode', () {
      final state = SettingsState();
      expect(state.uploadMode, UploadMode.simulate);
    });

    test('init() forces simulate even if prefs has production stored', () async {
      SharedPreferences.setMockInitialValues({
        'upload_mode': UploadMode.production.index,
      });

      final state = SettingsState();
      await state.init();

      expect(state.uploadMode, UploadMode.simulate);

      // Verify it persisted the override
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('upload_mode'), UploadMode.simulate.index);
    });

    test('init() forces simulate even if prefs has sandbox stored', () async {
      SharedPreferences.setMockInitialValues({
        'upload_mode': UploadMode.sandbox.index,
      });

      final state = SettingsState();
      await state.init();

      expect(state.uploadMode, UploadMode.simulate);
    });

    test('init() keeps simulate if already simulate', () async {
      SharedPreferences.setMockInitialValues({
        'upload_mode': UploadMode.simulate.index,
      });

      final state = SettingsState();
      await state.init();

      expect(state.uploadMode, UploadMode.simulate);
    });

    test('setUploadMode() allows simulate', () async {
      final state = SettingsState();
      await state.setUploadMode(UploadMode.simulate);

      expect(state.uploadMode, UploadMode.simulate);
    });
  });

  group('Endpoint registry', () {
    test('fresh install loads defaults for both registries', () async {
      final state = SettingsState();
      await state.init();

      expect(state.routingEndpoints, hasLength(2));
      expect(state.routingEndpoints[0].id, 'routing-deflock');
      expect(state.overpassEndpoints, hasLength(2));
      expect(state.overpassEndpoints[0].id, 'overpass-deflock');
    });

    test('registries return unmodifiable lists', () async {
      final state = SettingsState();
      await state.init();

      expect(
        () => state.routingEndpoints.add(
          const ServiceEndpoint(id: 'x', name: 'X', url: 'https://x.com'),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('registry mutations fire notifications', () async {
      final state = SettingsState();
      await state.init();

      int notifyCount = 0;
      state.addListener(() => notifyCount++);

      await state.routingRegistry.addOrUpdate(
        const ServiceEndpoint(id: 'custom', name: 'Custom', url: 'https://custom.com'),
      );
      expect(notifyCount, 1);
    });

    test('enabledRoutingEndpoints filters disabled entries', () async {
      final state = SettingsState();
      await state.init();

      // Disable the first routing endpoint
      final first = state.routingEndpoints[0];
      await state.routingRegistry.addOrUpdate(
        first.copyWith(enabled: false),
      );

      expect(state.enabledRoutingEndpoints, hasLength(1));
      expect(state.enabledRoutingEndpoints[0].id, 'routing-alprwatch');
    });
  });

  group('Endpoint migration', () {
    test('old routing_endpoint string migrates to registry list', () async {
      SharedPreferences.setMockInitialValues({
        'routing_endpoint': 'https://custom.example.com/route',
      });

      final state = SettingsState();
      await state.init();

      // Should have 3 endpoints: custom first, then 2 defaults
      expect(state.routingEndpoints, hasLength(3));
      expect(state.routingEndpoints[0].url, 'https://custom.example.com/route');
      expect(state.routingEndpoints[0].name, 'Custom');
      expect(state.routingEndpoints[1].id, 'routing-deflock');

      // Old key should be removed
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('routing_endpoint'), isFalse);
    });

    test('old overpass_endpoint string migrates to registry list', () async {
      SharedPreferences.setMockInitialValues({
        'overpass_endpoint': 'https://custom-overpass.example.com/api/interpreter',
      });

      final state = SettingsState();
      await state.init();

      expect(state.overpassEndpoints, hasLength(3));
      expect(state.overpassEndpoints[0].url, 'https://custom-overpass.example.com/api/interpreter');
    });

    test('old key matching a default URL does not create duplicate', () async {
      SharedPreferences.setMockInitialValues({
        'routing_endpoint': 'https://api.dontgetflocked.com/api/v1/deflock/directions',
      });

      final state = SettingsState();
      await state.init();

      // Should just have the 2 defaults, no duplicate custom entry
      expect(state.routingEndpoints, hasLength(2));
    });

    test('no old key with no new key creates defaults', () async {
      final state = SettingsState();
      await state.init();

      expect(state.routingEndpoints, hasLength(2));
      expect(state.overpassEndpoints, hasLength(2));
    });

    test('new format takes precedence over old format', () async {
      final existing = [
        const ServiceEndpoint(id: 'custom', name: 'Existing', url: 'https://existing.com'),
      ];
      SharedPreferences.setMockInitialValues({
        'routing_endpoint': 'https://old.example.com/route',
        'routing_endpoints': jsonEncode(existing.map((e) => e.toJson()).toList()),
      });

      final state = SettingsState();
      await state.init();

      // New format should take precedence; old key is NOT migrated when new exists
      // The registry should load existing + add missing defaults
      expect(state.routingEndpoints[0].url, 'https://existing.com');
    });

    test('migration is idempotent', () async {
      SharedPreferences.setMockInitialValues({
        'routing_endpoint': 'https://custom.example.com/route',
      });

      final state1 = SettingsState();
      await state1.init();
      final count1 = state1.routingEndpoints.length;

      // Init again (simulating app restart)
      final state2 = SettingsState();
      await state2.init();

      expect(state2.routingEndpoints.length, count1);
    });

    test('empty old endpoint string does not create custom entry', () async {
      SharedPreferences.setMockInitialValues({
        'routing_endpoint': '',
      });

      final state = SettingsState();
      await state.init();

      expect(state.routingEndpoints, hasLength(2));

      // Old key should be cleaned up
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('routing_endpoint'), isFalse);
    });
  });
}

