import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
