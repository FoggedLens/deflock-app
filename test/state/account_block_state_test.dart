import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deflockapp/services/osm_block_service.dart';
import 'package:deflockapp/state/account_block_state.dart';
import 'package:deflockapp/state/settings_state.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AccountBlockState', () {
    test('defaults to not blocked before init()', () {
      final state = AccountBlockState();
      expect(state.isBlocked, isFalse);
    });

    test('init() loads persisted blocked state for the given upload mode', () async {
      SharedPreferences.setMockInitialValues({
        'account_blocked_production': true,
      });

      final state = AccountBlockState();
      await state.init(UploadMode.production);

      expect(state.isBlocked, isTrue);
    });

    test('init() defaults to false when nothing is persisted', () async {
      final state = AccountBlockState();
      await state.init(UploadMode.production);

      expect(state.isBlocked, isFalse);
    });

    test('init() is scoped per upload mode', () async {
      SharedPreferences.setMockInitialValues({
        'account_blocked_production': true,
      });

      final state = AccountBlockState();
      await state.init(UploadMode.sandbox);

      expect(state.isBlocked, isFalse);
    });

    test('check() updates and persists state on a conclusive true result', () async {
      final client = MockClient((request) async => http.Response(
            '{"user_blocks":[{"id":1}]}',
            200,
          ));
      final state = AccountBlockState(blockService: OSMBlockService(client: client));
      await state.init(UploadMode.production);

      final result = await state.check(accessToken: 'token', uploadMode: UploadMode.production);

      expect(result, isTrue);
      expect(state.isBlocked, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('account_blocked_production'), isTrue);
    });

    test('check() updates and persists state on a conclusive false result', () async {
      SharedPreferences.setMockInitialValues({
        'account_blocked_production': true,
      });
      final client = MockClient((request) async => http.Response('{"user_blocks":[]}', 200));
      final state = AccountBlockState(blockService: OSMBlockService(client: client));
      await state.init(UploadMode.production);
      expect(state.isBlocked, isTrue);

      final result = await state.check(accessToken: 'token', uploadMode: UploadMode.production);

      expect(result, isFalse);
      expect(state.isBlocked, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('account_blocked_production'), isFalse);
    });

    test('check() leaves state unchanged on an inconclusive (null) result', () async {
      SharedPreferences.setMockInitialValues({
        'account_blocked_production': true,
      });
      final client = MockClient((request) async {
        throw Exception('offline');
      });
      final state = AccountBlockState(blockService: OSMBlockService(client: client));
      await state.init(UploadMode.production);
      expect(state.isBlocked, isTrue);

      final result = await state.check(accessToken: 'token', uploadMode: UploadMode.production);

      expect(result, isNull);
      expect(state.isBlocked, isTrue); // unchanged

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('account_blocked_production'), isTrue); // unchanged
    });

    test('clear() resets in-memory blocked state', () async {
      SharedPreferences.setMockInitialValues({
        'account_blocked_production': true,
      });
      final state = AccountBlockState();
      await state.init(UploadMode.production);
      expect(state.isBlocked, isTrue);

      state.clear();

      expect(state.isBlocked, isFalse);
    });
  });
}
