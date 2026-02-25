import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:deflockapp/dev_config.dart';
import 'package:deflockapp/services/http_client.dart';

void main() {
  group('UserAgentClient', () {
    test('adds User-Agent header to GET requests', () async {
      String? capturedUserAgent;

      final inner = MockClient((request) async {
        capturedUserAgent = request.headers['User-Agent'];
        return http.Response('ok', 200);
      });

      final client = UserAgentClient(inner);
      await client.get(Uri.parse('https://example.com'));

      expect(capturedUserAgent, isNotNull);
      expect(capturedUserAgent, startsWith('DeFlock/'));
      expect(capturedUserAgent, contains('+$kHomepageUrl'));
      expect(capturedUserAgent, contains('contact: $kContactEmail'));
    });

    test('adds User-Agent header to POST requests', () async {
      String? capturedUserAgent;

      final inner = MockClient((request) async {
        capturedUserAgent = request.headers['User-Agent'];
        return http.Response('ok', 200);
      });

      final client = UserAgentClient(inner);
      await client.post(
        Uri.parse('https://example.com'),
        body: json.encode({'key': 'value'}),
      );

      expect(capturedUserAgent, isNotNull);
      expect(capturedUserAgent, startsWith('DeFlock/'));
    });

    test('preserves existing headers alongside User-Agent', () async {
      Map<String, String>? capturedHeaders;

      final inner = MockClient((request) async {
        capturedHeaders = request.headers;
        return http.Response('ok', 200);
      });

      final client = UserAgentClient(inner);
      await client.get(
        Uri.parse('https://example.com'),
        headers: {'Authorization': 'Bearer token123'},
      );

      expect(capturedHeaders, isNotNull);
      expect(capturedHeaders!['Authorization'], equals('Bearer token123'));
      expect(capturedHeaders!['User-Agent'], startsWith('DeFlock/'));
    });

    test('does not overwrite a manually-set User-Agent', () async {
      String? capturedUserAgent;

      final inner = MockClient((request) async {
        capturedUserAgent = request.headers['User-Agent'];
        return http.Response('ok', 200);
      });

      final client = UserAgentClient(inner);
      await client.get(
        Uri.parse('https://example.com'),
        headers: {'User-Agent': 'CustomAgent/1.0'},
      );

      expect(capturedUserAgent, equals('CustomAgent/1.0'));
    });

    test('static userAgent getter returns expected format', () {
      final ua = UserAgentClient.userAgent;
      expect(ua, startsWith('DeFlock/'));
      expect(ua, contains('+$kHomepageUrl'));
      expect(ua, contains('contact: $kContactEmail'));
    });
  });
}
