import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deflockapp/services/auth_service.dart';
import 'package:deflockapp/state/auth_state.dart';
import 'package:deflockapp/state/settings_state.dart';

class MockAuthService extends Mock implements AuthService {}

void main() {
  late MockAuthService mockAuth;
  late AuthState state;

  setUpAll(() {
    registerFallbackValue(UploadMode.production);
  });

  setUp(() {
    mockAuth = MockAuthService();
    state = AuthState(authService: mockAuth);
  });

  group('init', () {
    test('uses restoreLoginLocal (not restoreLogin)', () async {
      when(() => mockAuth.setUploadMode(any())).thenReturn(null);
      when(() => mockAuth.isLoggedIn()).thenAnswer((_) async => true);
      when(() => mockAuth.restoreLoginLocal())
          .thenAnswer((_) async => 'LocalUser');

      await state.init(UploadMode.production);

      verify(() => mockAuth.restoreLoginLocal()).called(1);
      verifyNever(() => mockAuth.restoreLogin());
      expect(state.isLoggedIn, isTrue);
      expect(state.username, equals('LocalUser'));
    });

    test('considers user logged in when token exists but no cached display name', () async {
      when(() => mockAuth.setUploadMode(any())).thenReturn(null);
      when(() => mockAuth.isLoggedIn()).thenAnswer((_) async => true);
      when(() => mockAuth.restoreLoginLocal()).thenAnswer((_) async => '');

      await state.init(UploadMode.production);

      expect(state.isLoggedIn, isTrue);
      expect(state.username, equals(''));
    });

    test('not logged in when no stored session', () async {
      when(() => mockAuth.setUploadMode(any())).thenReturn(null);
      when(() => mockAuth.isLoggedIn()).thenAnswer((_) async => false);

      await state.init(UploadMode.production);

      expect(state.isLoggedIn, isFalse);
    });

    test('handles exception during init gracefully', () async {
      when(() => mockAuth.setUploadMode(any())).thenReturn(null);
      when(() => mockAuth.isLoggedIn()).thenThrow(Exception('storage error'));

      await state.init(UploadMode.production);

      expect(state.isLoggedIn, isFalse);
    });
  });

  group('refreshIfNeeded', () {
    test('updates username from restoreLogin', () async {
      when(() => mockAuth.isLoggedIn()).thenAnswer((_) async => true);
      when(() => mockAuth.restoreLogin())
          .thenAnswer((_) async => 'RefreshedUser');

      var notified = false;
      state.addListener(() => notified = true);

      await state.refreshIfNeeded();

      expect(state.username, equals('RefreshedUser'));
      expect(notified, isTrue);
    });

    test('does nothing when not logged in and username already null', () async {
      when(() => mockAuth.isLoggedIn()).thenAnswer((_) async => false);

      var notified = false;
      state.addListener(() => notified = true);

      await state.refreshIfNeeded();

      verifyNever(() => mockAuth.restoreLogin());
      expect(state.isLoggedIn, isFalse);
      expect(notified, isFalse); // No notification needed when nothing changed
    });

    test('clears username when token expired between init and refresh', () async {
      // Set up logged-in state via init
      when(() => mockAuth.setUploadMode(any())).thenReturn(null);
      when(() => mockAuth.isLoggedIn()).thenAnswer((_) async => true);
      when(() => mockAuth.restoreLoginLocal())
          .thenAnswer((_) async => 'User');
      await state.init(UploadMode.production);
      expect(state.isLoggedIn, isTrue);

      // Token expired — isLoggedIn now returns false
      when(() => mockAuth.isLoggedIn()).thenAnswer((_) async => false);

      await state.refreshIfNeeded();

      expect(state.isLoggedIn, isFalse);
      expect(state.username, equals(''));
    });

    test('skips notification when username unchanged', () async {
      // First set up logged-in state via init
      when(() => mockAuth.setUploadMode(any())).thenReturn(null);
      when(() => mockAuth.isLoggedIn()).thenAnswer((_) async => true);
      when(() => mockAuth.restoreLoginLocal())
          .thenAnswer((_) async => 'StableUser');
      await state.init(UploadMode.production);
      expect(state.username, equals('StableUser'));

      // Now refresh returns same username
      when(() => mockAuth.restoreLogin())
          .thenAnswer((_) async => 'StableUser');

      var notified = false;
      state.addListener(() => notified = true);

      await state.refreshIfNeeded();

      expect(state.username, equals('StableUser'));
      expect(notified, isFalse);
    });

    test('catches errors gracefully', () async {
      when(() => mockAuth.isLoggedIn()).thenThrow(Exception('network error'));

      await state.refreshIfNeeded();

      expect(state.isLoggedIn, isFalse);
    });
  });

  group('login', () {
    test('sets username on success', () async {
      when(() => mockAuth.login()).thenAnswer((_) async => 'NewUser');

      var notified = false;
      state.addListener(() => notified = true);

      await state.login();

      expect(state.isLoggedIn, isTrue);
      expect(state.username, equals('NewUser'));
      expect(notified, isTrue);
    });

    test('clears username on failure', () async {
      when(() => mockAuth.login()).thenThrow(Exception('network error'));

      await state.login();

      expect(state.isLoggedIn, isFalse);
    });
  });

  group('logout', () {
    test('clears state and notifies', () async {
      // Set up logged in state first
      when(() => mockAuth.login()).thenAnswer((_) async => 'User');
      await state.login();
      expect(state.isLoggedIn, isTrue);

      when(() => mockAuth.logout()).thenAnswer((_) async {});

      var notified = false;
      state.addListener(() => notified = true);

      await state.logout();

      expect(state.isLoggedIn, isFalse);
      expect(notified, isTrue);
    });
  });

  group('forceLogin', () {
    test('sets username on success', () async {
      when(() => mockAuth.forceLogin()).thenAnswer((_) async => 'ForcedUser');

      var notified = false;
      state.addListener(() => notified = true);

      await state.forceLogin();

      expect(state.isLoggedIn, isTrue);
      expect(state.username, equals('ForcedUser'));
      expect(notified, isTrue);
    });

    test('clears username on failure', () async {
      when(() => mockAuth.forceLogin()).thenThrow(Exception('OAuth error'));

      await state.forceLogin();

      expect(state.isLoggedIn, isFalse);
      expect(state.username, equals(''));
    });

    test('notifies listeners even on failure', () async {
      when(() => mockAuth.forceLogin()).thenThrow(Exception('OAuth error'));

      var notified = false;
      state.addListener(() => notified = true);

      await state.forceLogin();

      expect(notified, isTrue);
    });
  });

  group('onUploadModeChanged', () {
    test('refreshes auth for new mode', () async {
      when(() => mockAuth.setUploadMode(any())).thenReturn(null);
      when(() => mockAuth.isLoggedIn()).thenAnswer((_) async => true);
      when(() => mockAuth.restoreLogin())
          .thenAnswer((_) async => 'SandboxUser');

      await state.onUploadModeChanged(UploadMode.sandbox);

      verify(() => mockAuth.setUploadMode(UploadMode.sandbox)).called(1);
      expect(state.username, equals('SandboxUser'));
    });

    test('clears username when restoreLogin returns null for new mode', () async {
      when(() => mockAuth.setUploadMode(any())).thenReturn(null);
      when(() => mockAuth.isLoggedIn()).thenAnswer((_) async => true);
      when(() => mockAuth.restoreLogin()).thenAnswer((_) async => null);

      await state.onUploadModeChanged(UploadMode.sandbox);

      expect(state.isLoggedIn, isFalse);
      expect(state.username, equals(''));
    });

    test('clears username when not logged in for new mode', () async {
      // First set up a logged-in state
      when(() => mockAuth.login()).thenAnswer((_) async => 'User');
      await state.login();
      expect(state.isLoggedIn, isTrue);

      // Switch mode where user is not logged in
      when(() => mockAuth.setUploadMode(any())).thenReturn(null);
      when(() => mockAuth.isLoggedIn()).thenAnswer((_) async => false);

      await state.onUploadModeChanged(UploadMode.sandbox);

      expect(state.isLoggedIn, isFalse);
    });
  });
}
