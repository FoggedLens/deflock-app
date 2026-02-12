import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deflockapp/app_state.dart' show UploadMode;
import 'package:deflockapp/services/auth_service.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  late MockHttpClient mockClient;
  late AuthService service;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));

    // Mock FlutterSecureStorage platform channel so OAuth2Helper.removeAllTokens()
    // doesn't throw MissingPluginException in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async => null,
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockClient = MockHttpClient();
  });

  AuthService createService({UploadMode mode = UploadMode.production}) {
    return AuthService(mode: mode, client: mockClient);
  }

  group('restoreLogin', () {
    test('returns username when token exists and fetch succeeds', () async {
      SharedPreferences.setMockInitialValues({
        'osm_token_prod': jsonEncode({'accessToken': 'valid-token'}),
      });
      service = createService();

      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(
                jsonEncode({
                  'user': {'display_name': 'TestUser'}
                }),
                200,
              ));

      final result = await service.restoreLogin();

      expect(result, equals('TestUser'));
      expect(service.displayName, equals('TestUser'));
    });

    test('caches display name on successful fetch', () async {
      SharedPreferences.setMockInitialValues({
        'osm_token_prod': jsonEncode({'accessToken': 'valid-token'}),
      });
      service = createService();

      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(
                jsonEncode({
                  'user': {'display_name': 'CachedUser'}
                }),
                200,
              ));

      await service.restoreLogin();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cached_display_name_production'), equals('CachedUser'));
    });

    test('falls back to cached name on HTTP error', () async {
      SharedPreferences.setMockInitialValues({
        'osm_token_prod': jsonEncode({'accessToken': 'valid-token'}),
        'cached_display_name_production': 'PreviousUser',
      });
      service = createService();

      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('Server Error', 500));

      final result = await service.restoreLogin();

      expect(result, equals('PreviousUser'));
      expect(service.displayName, equals('PreviousUser'));
    });

    test('falls back to cached name on timeout', () async {
      SharedPreferences.setMockInitialValues({
        'osm_token_prod': jsonEncode({'accessToken': 'valid-token'}),
        'cached_display_name_production': 'TimeoutUser',
      });
      service = createService();

      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenThrow(http.ClientException('Connection timed out'));

      final result = await service.restoreLogin();

      expect(result, equals('TimeoutUser'));
      expect(service.displayName, equals('TimeoutUser'));
    });

    test('returns empty string when fetch fails and no cached name', () async {
      SharedPreferences.setMockInitialValues({
        'osm_token_prod': jsonEncode({'accessToken': 'valid-token'}),
      });
      service = createService();

      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('Server Error', 500));

      final result = await service.restoreLogin();

      expect(result, equals(''));
      expect(service.displayName, equals(''));
    });

    test('logs out on 401 (expired token) instead of falling back to cache',
        () async {
      SharedPreferences.setMockInitialValues({
        'osm_token_prod': jsonEncode({'accessToken': 'expired-token'}),
        'cached_display_name_production': 'StaleUser',
      });
      service = createService();

      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('Unauthorized', 401));

      final result = await service.restoreLogin();

      expect(result, isNull);
      expect(service.displayName, isNull);
      // Token should be cleared
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('osm_token_prod'), isNull);
    });

    test('logs out on 403 (forbidden) instead of falling back to cache',
        () async {
      SharedPreferences.setMockInitialValues({
        'osm_token_prod': jsonEncode({'accessToken': 'bad-token'}),
        'cached_display_name_production': 'StaleUser',
      });
      service = createService();

      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('Forbidden', 403));

      final result = await service.restoreLogin();

      expect(result, isNull);
      expect(service.displayName, isNull);
    });

    test('caches display name per mode (sandbox isolation)', () async {
      SharedPreferences.setMockInitialValues({
        'osm_token_sandbox': jsonEncode({'accessToken': 'sandbox-token'}),
      });
      service = createService(mode: UploadMode.sandbox);

      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(
                jsonEncode({
                  'user': {'display_name': 'SandboxUser'}
                }),
                200,
              ));

      await service.restoreLogin();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cached_display_name_sandbox'),
          equals('SandboxUser'));
      // Production cache should be untouched
      expect(prefs.getString('cached_display_name_production'), isNull);
    });

    test('returns null when no token stored', () async {
      SharedPreferences.setMockInitialValues({});
      service = createService();

      final result = await service.restoreLogin();

      expect(result, isNull);
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });

    test('returns Demo User in simulate mode when logged in', () async {
      SharedPreferences.setMockInitialValues({
        'sim_user_logged_in': true,
      });
      service = createService(mode: UploadMode.simulate);

      final result = await service.restoreLogin();

      expect(result, equals('Demo User'));
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });

    test('returns null in simulate mode when not logged in', () async {
      SharedPreferences.setMockInitialValues({});
      service = createService(mode: UploadMode.simulate);

      final result = await service.restoreLogin();

      expect(result, isNull);
    });
  });

  group('restoreLoginLocal', () {
    test('returns cached display name when token exists', () async {
      SharedPreferences.setMockInitialValues({
        'osm_token_prod': jsonEncode({'accessToken': 'valid-token'}),
        'cached_display_name_production': 'LocalUser',
      });
      service = createService();

      final result = await service.restoreLoginLocal();

      expect(result, equals('LocalUser'));
      expect(service.displayName, equals('LocalUser'));
      // Should NOT make any HTTP calls
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });

    test('returns empty string when token exists but no cached name', () async {
      SharedPreferences.setMockInitialValues({
        'osm_token_prod': jsonEncode({'accessToken': 'valid-token'}),
      });
      service = createService();

      final result = await service.restoreLoginLocal();

      expect(result, equals(''));
      expect(service.displayName, equals(''));
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });

    test('returns null when no token stored', () async {
      SharedPreferences.setMockInitialValues({});
      service = createService();

      final result = await service.restoreLoginLocal();

      expect(result, isNull);
    });

    test('returns Demo User in simulate mode', () async {
      SharedPreferences.setMockInitialValues({
        'sim_user_logged_in': true,
      });
      service = createService(mode: UploadMode.simulate);

      final result = await service.restoreLoginLocal();

      expect(result, equals('Demo User'));
      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });

    test('uses correct key per mode (sandbox)', () async {
      SharedPreferences.setMockInitialValues({
        'osm_token_sandbox': jsonEncode({'accessToken': 'sandbox-token'}),
        'cached_display_name_sandbox': 'SandboxLocal',
      });
      service = createService(mode: UploadMode.sandbox);

      final result = await service.restoreLoginLocal();

      expect(result, equals('SandboxLocal'));
    });
  });

  group('isLoggedIn', () {
    test('returns true when valid token exists', () async {
      SharedPreferences.setMockInitialValues({
        'osm_token_prod': jsonEncode({'accessToken': 'valid-token'}),
      });
      service = createService();

      expect(await service.isLoggedIn(), isTrue);
    });

    test('returns false when no token stored', () async {
      SharedPreferences.setMockInitialValues({});
      service = createService();

      expect(await service.isLoggedIn(), isFalse);
    });

    test('returns false for malformed JSON token', () async {
      SharedPreferences.setMockInitialValues({
        'osm_token_prod': 'not-valid-json',
      });
      service = createService();

      expect(await service.isLoggedIn(), isFalse);
    });

    test('sandbox mode uses correct key', () async {
      SharedPreferences.setMockInitialValues({
        'osm_token_sandbox': jsonEncode({'accessToken': 'sandbox-token'}),
      });
      service = createService(mode: UploadMode.sandbox);

      expect(await service.isLoggedIn(), isTrue);
    });

    test('returns true in simulate mode when sim_user_logged_in', () async {
      SharedPreferences.setMockInitialValues({
        'sim_user_logged_in': true,
      });
      service = createService(mode: UploadMode.simulate);

      expect(await service.isLoggedIn(), isTrue);
    });
  });

  group('getAccessToken', () {
    test('returns stored token', () async {
      SharedPreferences.setMockInitialValues({
        'osm_token_prod': jsonEncode({'accessToken': 'my-token'}),
      });
      service = createService();

      expect(await service.getAccessToken(), equals('my-token'));
    });

    test('returns sim-user-token in simulate mode', () async {
      SharedPreferences.setMockInitialValues({});
      service = createService(mode: UploadMode.simulate);

      expect(await service.getAccessToken(), equals('sim-user-token'));
    });

    test('returns null when no token stored', () async {
      SharedPreferences.setMockInitialValues({});
      service = createService();

      expect(await service.getAccessToken(), isNull);
    });
  });

  group('logout', () {
    test('clears token and cached display name', () async {
      SharedPreferences.setMockInitialValues({
        'osm_token_prod': jsonEncode({'accessToken': 'token'}),
        'cached_display_name_production': 'SomeUser',
      });
      service = createService();

      // First restore to set _displayName
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(
                jsonEncode({
                  'user': {'display_name': 'SomeUser'}
                }),
                200,
              ));
      await service.restoreLogin();
      expect(service.displayName, equals('SomeUser'));

      await service.logout();

      expect(service.displayName, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('osm_token_prod'), isNull);
      expect(prefs.getString('cached_display_name_production'), isNull);
    });

    test('clears sim_user_logged_in in simulate mode', () async {
      SharedPreferences.setMockInitialValues({
        'sim_user_logged_in': true,
      });
      service = createService(mode: UploadMode.simulate);

      await service.restoreLogin();
      expect(service.displayName, equals('Demo User'));

      await service.logout();

      expect(service.displayName, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sim_user_logged_in'), isNull);
    });
  });
}
