import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deflockapp/state/settings_state.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('forceLocationManager', () {
    test('defaults to false', () async {
      final state = SettingsState();
      await state.init();
      expect(state.forceLocationManager, false);
    });

    test('loads saved value from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'force_location_manager': true,
      });
      final state = SettingsState();
      await state.init();
      expect(state.forceLocationManager, true);
    });

    test('setter persists to SharedPreferences', () async {
      final state = SettingsState();
      await state.init();

      await state.setForceLocationManager(true);
      expect(state.forceLocationManager, true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('force_location_manager'), true);
    });

    test('setter notifies listeners on change', () async {
      final state = SettingsState();
      await state.init();

      int notifyCount = 0;
      state.addListener(() => notifyCount++);

      await state.setForceLocationManager(true);
      expect(notifyCount, 1);
    });

    test('setter does not notify when value unchanged', () async {
      final state = SettingsState();
      await state.init();

      int notifyCount = 0;
      state.addListener(() => notifyCount++);

      // Default is false, setting to false should be a no-op
      await state.setForceLocationManager(false);
      expect(notifyCount, 0);
    });

    test('round-trips through save and reload', () async {
      final state = SettingsState();
      await state.init();
      await state.setForceLocationManager(true);

      // Create a new instance and load from the same prefs
      final state2 = SettingsState();
      await state2.init();
      expect(state2.forceLocationManager, true);
    });
  });
}
