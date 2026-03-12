import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deflockapp/models/node_profile.dart';
import 'package:deflockapp/services/overpass_service.dart';
import 'package:deflockapp/services/service_policy.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  late MockHttpClient mockClient;
  late OverpassService service;

  final bounds = LatLngBounds(
    const LatLng(38.8, -77.1),
    const LatLng(39.0, -76.9),
  );

  final profiles = [
    NodeProfile(
      id: 'test-alpr',
      name: 'Test ALPR',
      tags: const {
        'man_made': 'surveillance',
        'surveillance:type': 'ALPR',
      },
    ),
  ];

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() {
    mockClient = MockHttpClient();
    // Initialize OverpassService with a mock HTTP client for testing
    service = OverpassService(client: mockClient);
  });

  /// Helper: stub a successful Overpass response with the given elements.
  void stubOverpassResponse(List<Map<String, dynamic>> elements) {
    when(() => mockClient.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => http.Response(
              jsonEncode({'elements': elements}),
              200,
            ));
  }

  /// Helper: stub an error response.
  void stubErrorResponse(int statusCode, String body) {
    when(() => mockClient.post(any(), body: any(named: 'body')))
        .thenAnswer((_) async => http.Response(body, statusCode));
  }

  group('query building', () {
    test('uses out skel for way/relation pass, out body for node pass',
        () async {
      stubOverpassResponse([]);

      await service.fetchNodes(bounds: bounds, profiles: profiles);

      final captured = verify(
        () => mockClient.post(any(), body: captureAny(named: 'body')),
      ).captured;

      final query = (captured.last as Map<String, String>)['data']!;
      expect(query, contains('out body;'));
      expect(query, contains('out skel;'));
      expect(query, isNot(contains('out meta;')));
    });

    test('empty tag values are excluded from filters', () async {
      final profileWithEmpty = [
        NodeProfile(
          id: 'test',
          name: 'Test',
          tags: const {
            'man_made': 'surveillance',
            'camera:mount': '', // empty — should be excluded
          },
        ),
      ];

      stubOverpassResponse([]);

      await service.fetchNodes(bounds: bounds, profiles: profileWithEmpty);

      final captured = verify(
        () => mockClient.post(any(), body: captureAny(named: 'body')),
      ).captured;

      final query = (captured.last as Map<String, String>)['data']!;
      expect(query, contains('["man_made"="surveillance"]'));
      expect(query, isNot(contains('camera:mount')));
    });
  });

  group('response parsing — constraint detection', () {
    test('nodes referenced by a way are constrained', () async {
      stubOverpassResponse([
        {
          'type': 'node',
          'id': 1,
          'lat': 38.9,
          'lon': -77.0,
          'tags': {'man_made': 'surveillance'},
        },
        {
          'type': 'node',
          'id': 2,
          'lat': 38.91,
          'lon': -77.01,
          'tags': {'man_made': 'surveillance'},
        },
        {
          'type': 'way',
          'id': 100,
          'nodes': [1],
        },
      ]);

      final nodes =
          await service.fetchNodes(bounds: bounds, profiles: profiles);

      expect(nodes, hasLength(2));
      final node1 = nodes.firstWhere((n) => n.id == 1);
      final node2 = nodes.firstWhere((n) => n.id == 2);
      expect(node1.isConstrained, isTrue);
      expect(node2.isConstrained, isFalse);
    });

    test('nodes referenced by a relation member are constrained', () async {
      stubOverpassResponse([
        {
          'type': 'node',
          'id': 3,
          'lat': 38.9,
          'lon': -77.0,
          'tags': {'man_made': 'surveillance'},
        },
        {
          'type': 'relation',
          'id': 200,
          'members': [
            {'type': 'node', 'ref': 3, 'role': ''},
          ],
        },
      ]);

      final nodes =
          await service.fetchNodes(bounds: bounds, profiles: profiles);

      expect(nodes, hasLength(1));
      expect(nodes.first.isConstrained, isTrue);
    });

    test('nodes not in any way or relation are unconstrained', () async {
      stubOverpassResponse([
        {
          'type': 'node',
          'id': 4,
          'lat': 38.9,
          'lon': -77.0,
          'tags': {'man_made': 'surveillance'},
        },
      ]);

      final nodes =
          await service.fetchNodes(bounds: bounds, profiles: profiles);

      expect(nodes, hasLength(1));
      expect(nodes.first.isConstrained, isFalse);
    });

    test('mixed response with nodes, ways, and relations', () async {
      stubOverpassResponse([
        {
          'type': 'node',
          'id': 10,
          'lat': 38.9,
          'lon': -77.0,
          'tags': {'man_made': 'surveillance'},
        },
        {
          'type': 'node',
          'id': 11,
          'lat': 38.91,
          'lon': -77.01,
          'tags': {'man_made': 'surveillance'},
        },
        {
          'type': 'node',
          'id': 12,
          'lat': 38.92,
          'lon': -77.02,
          'tags': {'man_made': 'surveillance'},
        },
        {
          'type': 'way',
          'id': 300,
          'nodes': [10],
        },
        {
          'type': 'relation',
          'id': 400,
          'members': [
            {'type': 'node', 'ref': 11, 'role': ''},
          ],
        },
      ]);

      final nodes =
          await service.fetchNodes(bounds: bounds, profiles: profiles);

      expect(nodes, hasLength(3));
      expect(nodes.firstWhere((n) => n.id == 10).isConstrained, isTrue);
      expect(nodes.firstWhere((n) => n.id == 11).isConstrained, isTrue);
      expect(nodes.firstWhere((n) => n.id == 12).isConstrained, isFalse);
    });
  });

  group('error handling', () {
    test('HTTP 200 returns parsed nodes', () async {
      stubOverpassResponse([
        {
          'type': 'node',
          'id': 1,
          'lat': 38.9,
          'lon': -77.0,
          'tags': {'man_made': 'surveillance'},
        },
      ]);

      final nodes =
          await service.fetchNodes(bounds: bounds, profiles: profiles);

      expect(nodes, hasLength(1));
      expect(nodes.first.id, equals(1));
    });

    test(
        'HTTP 400 with "too many nodes" and "50000" throws NodeLimitError',
        () async {
      stubErrorResponse(
          400, 'Error: too many nodes (limit is 50000) in query');

      await expectLater(
        () => service.fetchNodes(
            bounds: bounds, profiles: profiles, policy: const ResiliencePolicy(maxRetries: 0)),
        throwsA(isA<NodeLimitError>()),
      );
    });

    test('response with "timeout" throws NodeLimitError', () async {
      stubErrorResponse(400, 'runtime error: timeout in query execution');

      await expectLater(
        () => service.fetchNodes(
            bounds: bounds, profiles: profiles, policy: const ResiliencePolicy(maxRetries: 0)),
        throwsA(isA<NodeLimitError>()),
      );
    });

    test('response with "runtime limit exceeded" throws NodeLimitError',
        () async {
      stubErrorResponse(400, 'runtime limit exceeded');

      await expectLater(
        () => service.fetchNodes(
            bounds: bounds, profiles: profiles, policy: const ResiliencePolicy(maxRetries: 0)),
        throwsA(isA<NodeLimitError>()),
      );
    });

    test('HTTP 429 throws RateLimitError', () async {
      stubErrorResponse(429, 'Too Many Requests');

      await expectLater(
        () => service.fetchNodes(
            bounds: bounds, profiles: profiles, policy: const ResiliencePolicy(maxRetries: 0)),
        throwsA(isA<RateLimitError>()),
      );
    });

    test('response with "rate limited" throws RateLimitError', () async {
      stubErrorResponse(503, 'You are rate limited');

      await expectLater(
        () => service.fetchNodes(
            bounds: bounds, profiles: profiles, policy: const ResiliencePolicy(maxRetries: 0)),
        throwsA(isA<RateLimitError>()),
      );
    });

    test('other HTTP errors with retries exhausted throws NetworkError',
        () async {
      stubErrorResponse(500, 'Internal Server Error');

      await expectLater(
        () => service.fetchNodes(
            bounds: bounds, profiles: profiles, policy: const ResiliencePolicy(maxRetries: 0)),
        throwsA(isA<NetworkError>()),
      );
    });

    test('empty profiles returns empty list without making request',
        () async {
      final nodes = await service.fetchNodes(bounds: bounds, profiles: []);

      expect(nodes, isEmpty);
      verifyNever(() => mockClient.post(any(), body: any(named: 'body')));
    });
  });

  group('fallback behavior', () {
    test('falls back to overpass-api.de on NetworkError after retries', () async {
      int callCount = 0;
      when(() => mockClient.post(any(), body: any(named: 'body')))
          .thenAnswer((invocation) async {
        callCount++;
        final uri = invocation.positionalArguments[0] as Uri;

        if (uri.host == 'overpass.deflock.org') {
          return http.Response('Internal Server Error', 500);
        }
        // Fallback succeeds
        return http.Response(
          jsonEncode({
            'elements': [
              {
                'type': 'node',
                'id': 1,
                'lat': 38.9,
                'lon': -77.0,
                'tags': {'man_made': 'surveillance'},
              },
            ]
          }),
          200,
        );
      });

      final nodes = await service.fetchNodes(
          bounds: bounds, profiles: profiles, policy: const ResiliencePolicy(maxRetries: 0));

      expect(nodes, hasLength(1));
      // primary (1 attempt, 0 retries) + fallback (1 attempt) = 2
      expect(callCount, equals(2));
    });

    test('does NOT fallback on NodeLimitError', () async {
      when(() => mockClient.post(any(), body: any(named: 'body')))
          .thenAnswer((_) async => http.Response(
                'Error: too many nodes (limit is 50000) in query',
                400,
              ));

      await expectLater(
        () => service.fetchNodes(
            bounds: bounds, profiles: profiles, policy: const ResiliencePolicy(maxRetries: 0)),
        throwsA(isA<NodeLimitError>()),
      );

      // Only one call — no fallback (abort disposition)
      verify(() => mockClient.post(any(), body: any(named: 'body')))
          .called(1);
    });

    test('RateLimitError triggers fallback without retrying primary', () async {
      int callCount = 0;
      when(() => mockClient.post(any(), body: any(named: 'body')))
          .thenAnswer((invocation) async {
        callCount++;
        final uri = invocation.positionalArguments[0] as Uri;

        if (uri.host == 'overpass.deflock.org') {
          return http.Response('Too Many Requests', 429);
        }
        // Fallback succeeds
        return http.Response(
          jsonEncode({
            'elements': [
              {
                'type': 'node',
                'id': 1,
                'lat': 38.9,
                'lon': -77.0,
                'tags': {'man_made': 'surveillance'},
              },
            ]
          }),
          200,
        );
      });

      final nodes = await service.fetchNodes(
          bounds: bounds, profiles: profiles, policy: const ResiliencePolicy(maxRetries: 2));

      expect(nodes, hasLength(1));
      // 1 primary (no retry on fallback disposition) + 1 fallback = 2
      expect(callCount, equals(2));
    });

    test('primary fails then fallback also fails -> error propagated', () async {
      when(() => mockClient.post(any(), body: any(named: 'body')))
          .thenAnswer((_) async =>
              http.Response('Internal Server Error', 500));

      await expectLater(
        () => service.fetchNodes(
            bounds: bounds, profiles: profiles, policy: const ResiliencePolicy(maxRetries: 0)),
        throwsA(isA<NetworkError>()),
      );

      // primary + fallback
      verify(() => mockClient.post(any(), body: any(named: 'body')))
          .called(2);
    });

    test('does NOT fallback when using custom endpoint', () async {
      final customService = OverpassService(
        client: mockClient,
        endpoint: 'https://custom.example.com/api/interpreter',
      );

      when(() => mockClient.post(any(), body: any(named: 'body')))
          .thenAnswer((_) async =>
              http.Response('Internal Server Error', 500));

      await expectLater(
        () => customService.fetchNodes(
            bounds: bounds, profiles: profiles, policy: const ResiliencePolicy(maxRetries: 0)),
        throwsA(isA<NetworkError>()),
      );

      // Only one call - no fallback with custom endpoint
      verify(() => mockClient.post(any(), body: any(named: 'body')))
          .called(1);
    });

    test('retries exhaust before fallback kicks in', () async {
      int callCount = 0;
      when(() => mockClient.post(any(), body: any(named: 'body')))
          .thenAnswer((invocation) async {
        callCount++;
        final uri = invocation.positionalArguments[0] as Uri;

        if (uri.host == 'overpass.deflock.org') {
          return http.Response('Server Error', 500);
        }
        // Fallback succeeds
        return http.Response(
          jsonEncode({
            'elements': [
              {
                'type': 'node',
                'id': 1,
                'lat': 38.9,
                'lon': -77.0,
                'tags': {'man_made': 'surveillance'},
              },
            ]
          }),
          200,
        );
      });

      final nodes = await service.fetchNodes(
          bounds: bounds, profiles: profiles, policy: const ResiliencePolicy(maxRetries: 2));

      expect(nodes, hasLength(1));
      // 3 primary attempts (1 + 2 retries) + 1 fallback = 4
      expect(callCount, equals(4));
    });
  });

  group('default endpoints', () {
    test('default endpoint is overpass.deflock.org', () {
      expect(OverpassService.defaultEndpoint,
          equals('https://overpass.deflock.org/api/interpreter'));
    });

    test('fallback endpoint is overpass-api.de', () {
      expect(OverpassService.fallbackEndpoint,
          equals('https://overpass-api.de/api/interpreter'));
    });
  });
}
