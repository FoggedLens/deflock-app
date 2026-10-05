import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:deflockapp/services/osm_block_service.dart';
import 'package:deflockapp/state/settings_state.dart';

void main() {
  group('OSMBlockService', () {
    test('returns null in simulate mode without making a request', () async {
      var requested = false;
      final client = MockClient((request) async {
        requested = true;
        return http.Response('{"user_blocks":[]}', 200);
      });
      final service = OSMBlockService(client: client);

      final result = await service.checkActiveBlock(
        accessToken: 'token',
        uploadMode: UploadMode.simulate,
      );

      expect(result, isNull);
      expect(requested, isFalse);
    });

    test('returns null when access token is null', () async {
      final client = MockClient((request) async => http.Response('{"user_blocks":[]}', 200));
      final service = OSMBlockService(client: client);

      final result = await service.checkActiveBlock(
        accessToken: null,
        uploadMode: UploadMode.production,
      );

      expect(result, isNull);
    });

    test('returns null when access token is empty', () async {
      final client = MockClient((request) async => http.Response('{"user_blocks":[]}', 200));
      final service = OSMBlockService(client: client);

      final result = await service.checkActiveBlock(
        accessToken: '',
        uploadMode: UploadMode.production,
      );

      expect(result, isNull);
    });

    test('returns false when user_blocks is empty', () async {
      final client = MockClient((request) async => http.Response('{"user_blocks":[]}', 200));
      final service = OSMBlockService(client: client);

      final result = await service.checkActiveBlock(
        accessToken: 'token',
        uploadMode: UploadMode.production,
      );

      expect(result, isFalse);
    });

    test('returns true when user_blocks is non-empty', () async {
      final client = MockClient((request) async => http.Response(
            '{"user_blocks":[{"id":101,"needs_view":true}]}',
            200,
          ));
      final service = OSMBlockService(client: client);

      final result = await service.checkActiveBlock(
        accessToken: 'token',
        uploadMode: UploadMode.production,
      );

      expect(result, isTrue);
    });

    test('sends the request to the correct production host with auth header', () async {
      Uri? capturedUri;
      String? capturedAuth;
      final client = MockClient((request) async {
        capturedUri = request.url;
        capturedAuth = request.headers['Authorization'];
        return http.Response('{"user_blocks":[]}', 200);
      });
      final service = OSMBlockService(client: client);

      await service.checkActiveBlock(
        accessToken: 'my-token',
        uploadMode: UploadMode.production,
      );

      expect(capturedUri?.host, 'api.openstreetmap.org');
      expect(capturedUri?.path, '/api/0.6/user/blocks/active.json');
      expect(capturedAuth, 'Bearer my-token');
    });

    test('sends the request to the sandbox host in sandbox mode', () async {
      Uri? capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return http.Response('{"user_blocks":[]}', 200);
      });
      final service = OSMBlockService(client: client);

      await service.checkActiveBlock(
        accessToken: 'my-token',
        uploadMode: UploadMode.sandbox,
      );

      expect(capturedUri?.host, 'api06.dev.openstreetmap.org');
    });

    test('returns null on non-200 response', () async {
      final client = MockClient((request) async => http.Response('Unauthorized', 401));
      final service = OSMBlockService(client: client);

      final result = await service.checkActiveBlock(
        accessToken: 'token',
        uploadMode: UploadMode.production,
      );

      expect(result, isNull);
    });

    test('returns null on malformed JSON response', () async {
      final client = MockClient((request) async => http.Response('not json', 200));
      final service = OSMBlockService(client: client);

      final result = await service.checkActiveBlock(
        accessToken: 'token',
        uploadMode: UploadMode.production,
      );

      expect(result, isNull);
    });

    test('returns null when user_blocks field is missing', () async {
      final client = MockClient((request) async => http.Response('{}', 200));
      final service = OSMBlockService(client: client);

      final result = await service.checkActiveBlock(
        accessToken: 'token',
        uploadMode: UploadMode.production,
      );

      expect(result, isNull);
    });

    test('returns null when the client throws (e.g. no network)', () async {
      final client = MockClient((request) async {
        throw Exception('network error');
      });
      final service = OSMBlockService(client: client);

      final result = await service.checkActiveBlock(
        accessToken: 'token',
        uploadMode: UploadMode.production,
      );

      expect(result, isNull);
    });
  });
}
