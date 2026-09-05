import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deflockapp/app_state.dart';
import 'package:deflockapp/models/node_profile.dart';
import 'package:deflockapp/services/node_data_manager.dart';
import 'package:deflockapp/services/overpass_service.dart';

/// Issue #109 regression tests: when Overpass reports its 50k node limit and
/// the area is split into quadrants, quadrant fetches must run concurrently
/// (bounded), not strictly one-at-a-time.
///
/// The HTTP layer is faked with a scripted client — no real requests. The
/// first (whole-area) request answers with Overpass's "too many nodes" 400
/// body, which makes NodeDataManager split into 4 quadrants. Quadrant
/// responses can be held pending on completers, which is how the tests
/// observe whether quadrant fetches overlap in time.
void main() {
  final bounds = LatLngBounds(
    const LatLng(40.70, -74.02),
    const LatLng(40.72, -74.00),
  );

  final profile = NodeProfile(
    id: 'test-profile',
    name: 'Test Profile',
    tags: const {'man_made': 'surveillance'},
  );

  late _ScriptedClient client;
  late NodeDataManager manager;

  setUp(() {
    final mockAppState = MockAppState();
    when(() => mockAppState.offlineMode).thenReturn(false);
    AppState.instance = mockAppState;

    client = _ScriptedClient();
    manager = NodeDataManager.forTesting(
      overpass: OverpassService(client: client),
    );
  });

  tearDown(() {
    AppState.instance = MockAppState();
  });

  test('split quadrant fetches overlap in time (not sequential)', () async {
    // Whole-area request: Overpass 400 "too many nodes" -> triggers split.
    client.scriptImmediate(_nodeLimitResponse());
    // The 4 quadrant requests: each stays pending until the test releases it.
    final gates = List.generate(4, (_) => Completer<http.Response>());
    for (final gate in gates) {
      client.scriptPending(gate);
    }

    final future = manager.getNodesFor(bounds: bounds, profiles: [profile]);

    // Let the split logic run. Sequential execution leaves exactly 1
    // quadrant request pending (the other 3 never start); concurrent
    // execution has all 4 pending at once.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(client.startedCount, 5,
        reason: 'whole-area request plus all 4 quadrant requests should '
            'have been issued');
    expect(client.pendingCount, 4,
        reason: 'all 4 quadrant fetches should be in flight simultaneously; '
            'sequential execution never starts more than one');

    for (final gate in gates) {
      gate.complete(_emptySuccess());
    }
    final nodes = await future;
    expect(nodes, isEmpty);
  });

  test('nested split fetches are bounded, not all in flight at once', () async {
    // Whole area hits the node limit -> 4 quadrant fetches start.
    // Every quadrant also hits the node limit -> each spawns 4 more
    // sub-quadrant fetches (16 total leaf fetches), all held pending.
    client.scriptImmediate(_nodeLimitResponse());
    for (var i = 0; i < 4; i++) {
      client.scriptImmediate(_nodeLimitResponse());
    }
    final gates = List.generate(16, (_) => Completer<http.Response>());
    for (final gate in gates) {
      client.scriptPending(gate);
    }

    final future = manager.getNodesFor(bounds: bounds, profiles: [profile]);

    await Future<void>.delayed(const Duration(milliseconds: 300));

    // With concurrency bounded at 4, at most 4 of the 16 held leaf requests
    // may be in flight at once (the 5 script entries that answered the node
    // limit have already completed and released their slots).
    expect(
      client.pendingCount,
      lessThanOrEqualTo(4),
      reason: 'nested split fetches must be capped, not all 16 in flight',
    );

    for (final gate in gates) {
      gate.complete(_emptySuccess());
    }
    final nodes = await future;
    expect(nodes, isEmpty);
  });

  test('a failed quadrant does not abort the remaining quadrants', () async {
    // Whole area hits the node limit -> split into 4 quadrants.
    client.scriptImmediate(_nodeLimitResponse());

    // One quadrant fails permanently: retry disposition means the policy
    // tries 1 + maxRetries(3) attempts against the primary endpoint, then
    // the same 4 attempts against the fallback endpoint = 8 failures total.
    for (var i = 0; i < 8; i++) {
      client.scriptImmediate(_serverErrorResponse());
    }

    // The other 3 quadrants succeed. Concurrent quadrant starts interleave
    // with the failing quadrant's retry cycle, so exact per-request order
    // is not deterministic — answer anything else with a one-node success.
    client.defaultResponse = _singleNodeSuccess;

    final nodes = await manager.getNodesFor(
      bounds: bounds,
      profiles: [profile],
    );

    // The 3 successful quadrants each returned a node; the failed quadrant
    // contributed nothing and did not abort the split.
    expect(nodes.length, greaterThanOrEqualTo(3));
  });
}

class MockAppState extends Mock implements AppState {}

http.Response _nodeLimitResponse() => http.Response(
      'runtime error: Query returned too many nodes (over 50000)',
      400,
    );

http.Response _emptySuccess() => http.Response('{"elements": []}', 200);

http.Response _serverErrorResponse() => http.Response('server error', 500);

http.Response _singleNodeSuccess() => http.Response(
      '{"elements": [{"type": "node", "id": 1, "lat": 40.71, "lon": -74.01,'
      ' "tags": {"man_made": "surveillance"}}]}',
      200,
    );

/// http.Client whose responses come from a FIFO script. Tracks how many
/// requests have started and how many are currently pending.
class _ScriptedClient extends http.BaseClient {
  final _Queue<_ScriptedResponse> _script = _Queue();
  http.Response Function()? defaultResponse;

  int startedCount = 0;
  int _pendingCount = 0;

  int get pendingCount => _pendingCount;

  void scriptImmediate(http.Response response) =>
      _script.add(_ScriptedResponse(response, null));

  void scriptPending(Completer<http.Response> gate) =>
      _script.add(_ScriptedResponse(null, gate));

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    startedCount++;
    _pendingCount++;
    try {
      http.Response response;
      if (_script.isNotEmpty) {
        final entry = _script.removeFirst();
        if (entry.gate != null) {
          response = await entry.gate!.future;
        } else {
          response = entry.response!;
        }
      } else {
        final fallback = defaultResponse;
        if (fallback != null) {
          response = fallback();
        } else {
          throw StateError('ScriptedClient: no scripted response for ${request.url}');
        }
      }
      return http.StreamedResponse(
        http.ByteStream.fromBytes(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
        request: request,
      );
    } finally {
      _pendingCount--;
    }
  }
}

class _ScriptedResponse {
  final http.Response? response;
  final Completer<http.Response>? gate;

  _ScriptedResponse(this.response, this.gate);
}

/// Minimal FIFO queue (avoids importing dart:collection just for this).
class _Queue<T> {
  final _items = <T>[];

  void add(T item) => _items.add(item);

  bool get isNotEmpty => _items.isNotEmpty;

  T removeFirst() => _items.removeAt(0);
}
