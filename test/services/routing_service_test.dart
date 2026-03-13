import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deflockapp/app_state.dart';
import 'package:deflockapp/models/node_profile.dart';
import 'package:deflockapp/models/service_endpoint.dart';
import 'package:deflockapp/services/routing_service.dart';

class MockHttpClient extends Mock implements http.Client {}

class MockAppState extends Mock implements AppState {}

void main() {
  late MockHttpClient mockClient;
  late MockAppState mockAppState;
  late RoutingService service;

  final start = const LatLng(38.9, -77.0);
  final end = const LatLng(39.0, -77.1);

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'navigation_avoidance_distance': 100,
    });

    mockClient = MockHttpClient();
    mockAppState = MockAppState();
    AppState.instance = mockAppState;

    // Use fixed endpoints so tests don't try to resolve AppState settings
    service = RoutingService(
      client: mockClient,
      endpoints: DefaultServiceEndpoints.routing(),
    );
  });

  tearDown(() {
    AppState.instance = MockAppState();
  });

  /// Helper: stub a successful routing response
  void stubSuccessResponse() {
    when(() => mockClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        )).thenAnswer((_) async => http.Response(
          json.encode({
            'ok': true,
            'result': {
              'route': {
                'coordinates': [
                  [-77.0, 38.9],
                  [-77.1, 39.0],
                ],
                'distance': 1000.0,
                'duration': 600.0,
              },
            },
          }),
          200,
        ));
  }

  group('RoutingService', () {
    test('empty tags are filtered from request body', () async {
      // Profile with empty tag values (like builtin-flock has camera:mount: '')
      final profiles = [
        NodeProfile(
          id: 'test-profile',
          name: 'Test Profile',
          tags: const {
            'man_made': 'surveillance',
            'surveillance:type': 'ALPR',
            'camera:mount': '', // empty value - should be filtered
          },
        ),
      ];
      when(() => mockAppState.enabledProfiles).thenReturn(profiles);

      stubSuccessResponse();

      await service.calculateRoute(start: start, end: end);

      final captured = verify(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          )).captured;

      final body = json.decode(captured.last as String) as Map<String, dynamic>;
      final enabledProfiles = body['enabled_profiles'] as List<dynamic>;
      final tags = enabledProfiles[0]['tags'] as Map<String, dynamic>;

      // camera:mount with empty value should be stripped
      expect(tags.containsKey('camera:mount'), isFalse);
      // Non-empty tags should remain
      expect(tags['man_made'], equals('surveillance'));
      expect(tags['surveillance:type'], equals('ALPR'));
    });

    test('successful route parsing', () async {
      when(() => mockAppState.enabledProfiles).thenReturn([]);

      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(
            json.encode({
              'ok': true,
              'result': {
                'route': {
                  'coordinates': [
                    [-77.0, 38.9],
                    [-77.05, 38.95],
                    [-77.1, 39.0],
                  ],
                  'distance': 15000.0,
                  'duration': 1200.0,
                },
              },
            }),
            200,
          ));

      final result = await service.calculateRoute(start: start, end: end);

      expect(result.waypoints, hasLength(3));
      expect(result.waypoints.first.latitude, equals(38.9));
      expect(result.waypoints.first.longitude, equals(-77.0));
      expect(result.distanceMeters, equals(15000.0));
      expect(result.durationSeconds, equals(1200.0));
    });

    test('HTTP error throws RoutingException with status code', () async {
      when(() => mockAppState.enabledProfiles).thenReturn([]);

      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(
            'Bad Request',
            400,
            reasonPhrase: 'Bad Request',
          ));

      await expectLater(
        () => service.calculateRoute(start: start, end: end),
        throwsA(isA<RoutingException>().having(
          (e) => e.message,
          'message',
          contains('400'),
        )),
      );
    });

    test('network error is wrapped in RoutingException', () async {
      when(() => mockAppState.enabledProfiles).thenReturn([]);

      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenThrow(http.ClientException('Connection refused'));

      await expectLater(
        () => service.calculateRoute(start: start, end: end),
        throwsA(isA<RoutingException>().having(
          (e) => e.message,
          'message',
          startsWith('Network error:'),
        )),
      );
    });

    test('API-level error surfaces message', () async {
      when(() => mockAppState.enabledProfiles).thenReturn([]);

      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(
            json.encode({
              'ok': false,
              'error': 'Invalid profile configuration',
            }),
            200,
          ));

      await expectLater(
        () => service.calculateRoute(start: start, end: end),
        throwsA(isA<RoutingException>().having(
          (e) => e.message,
          'message',
          contains('Invalid profile configuration'),
        )),
      );
    });
  });

  group('fallback behavior', () {
    test('falls back to secondary on server error (500) after retries', () async {
      when(() => mockAppState.enabledProfiles).thenReturn([]);

      int callCount = 0;
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((invocation) async {
        callCount++;
        final uri = invocation.positionalArguments[0] as Uri;

        if (uri.host == 'api.dontgetflocked.com') {
          return http.Response('Internal Server Error', 500,
              reasonPhrase: 'Internal Server Error');
        }
        // Fallback succeeds
        return http.Response(
          json.encode({
            'ok': true,
            'result': {
              'route': {
                'coordinates': [
                  [-77.0, 38.9],
                  [-77.1, 39.0],
                ],
                'distance': 5000.0,
                'duration': 300.0,
              },
            },
          }),
          200,
        );
      });

      final result = await service.calculateRoute(start: start, end: end);
      expect(result.distanceMeters, equals(5000.0));
      // 2 primary attempts (1 + 1 retry) + 1 fallback = 3
      expect(callCount, equals(3));
    });

    test('falls back on 502 (GraphHopper unavailable) after retries', () async {
      when(() => mockAppState.enabledProfiles).thenReturn([]);

      int callCount = 0;
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((invocation) async {
        callCount++;
        final uri = invocation.positionalArguments[0] as Uri;
        if (uri.host == 'api.dontgetflocked.com') {
          return http.Response('Bad Gateway', 502, reasonPhrase: 'Bad Gateway');
        }
        return http.Response(
          json.encode({
            'ok': true,
            'result': {
              'route': {
                'coordinates': [[-77.0, 38.9]],
                'distance': 100.0,
                'duration': 60.0,
              },
            },
          }),
          200,
        );
      });

      final result = await service.calculateRoute(start: start, end: end);
      expect(result.distanceMeters, equals(100.0));
      // 2 primary attempts + 1 fallback = 3
      expect(callCount, equals(3));
    });

    test('falls back on network error after retries', () async {
      when(() => mockAppState.enabledProfiles).thenReturn([]);

      int callCount = 0;
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((invocation) async {
        callCount++;
        final uri = invocation.positionalArguments[0] as Uri;
        if (uri.host == 'api.dontgetflocked.com') {
          throw http.ClientException('Connection refused');
        }
        return http.Response(
          json.encode({
            'ok': true,
            'result': {
              'route': {
                'coordinates': [[-77.0, 38.9]],
                'distance': 100.0,
                'duration': 60.0,
              },
            },
          }),
          200,
        );
      });

      final result = await service.calculateRoute(start: start, end: end);
      expect(result.distanceMeters, equals(100.0));
      // 2 primary attempts + 1 fallback = 3
      expect(callCount, equals(3));
    });

    test('429 triggers fallback without retrying primary', () async {
      when(() => mockAppState.enabledProfiles).thenReturn([]);

      int callCount = 0;
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((invocation) async {
        callCount++;
        final uri = invocation.positionalArguments[0] as Uri;
        if (uri.host == 'api.dontgetflocked.com') {
          return http.Response('Too Many Requests', 429,
              reasonPhrase: 'Too Many Requests');
        }
        return http.Response(
          json.encode({
            'ok': true,
            'result': {
              'route': {
                'coordinates': [[-77.0, 38.9]],
                'distance': 200.0,
                'duration': 120.0,
              },
            },
          }),
          200,
        );
      });

      final result = await service.calculateRoute(start: start, end: end);
      expect(result.distanceMeters, equals(200.0));
      // 1 primary (no retry on 429/fallback disposition) + 1 fallback = 2
      expect(callCount, equals(2));
    });

    test('does NOT fallback on 400 (validation error)', () async {
      when(() => mockAppState.enabledProfiles).thenReturn([]);

      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(
            'Bad Request: missing start', 400,
            reasonPhrase: 'Bad Request'));

      await expectLater(
        () => service.calculateRoute(start: start, end: end),
        throwsA(isA<RoutingException>().having(
          (e) => e.statusCode, 'statusCode', 400)),
      );

      // Only one call — no retry, no fallback (abort disposition)
      verify(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).called(1);
    });

    test('does NOT fallback on 403 (all 4xx except 429 abort)', () async {
      when(() => mockAppState.enabledProfiles).thenReturn([]);

      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(
            'Forbidden', 403,
            reasonPhrase: 'Forbidden'));

      await expectLater(
        () => service.calculateRoute(start: start, end: end),
        throwsA(isA<RoutingException>().having(
          (e) => e.statusCode, 'statusCode', 403)),
      );

      // Only one call — no retry, no fallback (abort disposition)
      verify(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).called(1);
    });

    test('does NOT fallback on API-level business logic errors', () async {
      when(() => mockAppState.enabledProfiles).thenReturn([]);

      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(
            json.encode({
              'ok': false,
              'error': 'No route found',
            }),
            200,
          ));

      await expectLater(
        () => service.calculateRoute(start: start, end: end),
        throwsA(isA<RoutingException>().having(
          (e) => e.isApiError, 'isApiError', true)),
      );

      verify(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).called(1);
    });

    test('primary fails then fallback also fails -> error propagated', () async {
      when(() => mockAppState.enabledProfiles).thenReturn([]);

      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(
            'Internal Server Error', 500,
            reasonPhrase: 'Internal Server Error'));

      await expectLater(
        () => service.calculateRoute(start: start, end: end),
        throwsA(isA<RoutingException>().having(
          (e) => e.statusCode, 'statusCode', 500)),
      );

      // 2 primary attempts + 2 fallback attempts = 4
      verify(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).called(4);
    });

    test('single custom endpoint does not fallback', () async {
      final customService = RoutingService(
        client: mockClient,
        endpoints: const [
          ServiceEndpoint(id: 'custom', name: 'Custom', url: 'https://custom.example.com/route'),
        ],
      );

      when(() => mockAppState.enabledProfiles).thenReturn([]);

      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => http.Response(
            'Service Unavailable', 503,
            reasonPhrase: 'Service Unavailable'));

      await expectLater(
        () => customService.calculateRoute(start: start, end: end),
        throwsA(isA<RoutingException>()),
      );

      // 2 attempts (1 + 1 retry), no fallback with single endpoint
      verify(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).called(2);
    });
  });

  group('RoutingException', () {
    test('statusCode is preserved', () {
      const e = RoutingException('test', statusCode: 502);
      expect(e.statusCode, 502);
      expect(e.isApiError, false);
    });

    test('isApiError flag works', () {
      const e = RoutingException('test', isApiError: true);
      expect(e.isApiError, true);
      expect(e.statusCode, isNull);
    });
  });
}
