import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deflockapp/app_state.dart';
import 'package:deflockapp/models/node_profile.dart';
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

    service = RoutingService(client: mockClient);
  });

  tearDown(() {
    AppState.instance = MockAppState();
  });

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

      // Capture the request body
      when(() => mockClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((invocation) async {
        return http.Response(
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
        );
      });

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

      expect(
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

      expect(
        () => service.calculateRoute(start: start, end: end),
        throwsA(isA<RoutingException>().having(
          (e) => e.message,
          'message',
          startsWith('Network error:'),
        )),
      );
    });

    test('API-level error surfaces alprwatch message', () async {
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

      expect(
        () => service.calculateRoute(start: start, end: end),
        throwsA(isA<RoutingException>().having(
          (e) => e.message,
          'message',
          contains('Invalid profile configuration'),
        )),
      );
    });
  });
}
