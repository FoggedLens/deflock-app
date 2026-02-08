import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deflockapp/state/upload_queue_state.dart';
import 'package:deflockapp/state/session_state.dart';
import 'package:deflockapp/state/settings_state.dart';
import 'package:deflockapp/models/node_profile.dart';
import 'package:deflockapp/models/operator_profile.dart';
import 'package:deflockapp/models/osm_node.dart';
import 'package:deflockapp/models/pending_upload.dart';
import 'package:deflockapp/services/map_data_provider.dart';
import 'package:deflockapp/widgets/node_provider_with_cache.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockMapDataProvider extends Mock implements MapDataProvider {}

class MockNodeProviderWithCache extends Mock implements NodeProviderWithCache {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

NodeProfile _flockProfile() => NodeProfile(
      id: 'flock',
      name: 'Flock',
      tags: const {
        'man_made': 'surveillance',
        'surveillance': 'public',
        'surveillance:type': 'ALPR',
        'camera:mount': '',
        'manufacturer': 'Flock Safety',
      },
      submittable: true,
      requiresDirection: true,
    );

NodeProfile _flockProfileWithFov() => NodeProfile(
      id: 'flock-fov',
      name: 'Flock',
      tags: const {
        'man_made': 'surveillance',
        'surveillance': 'public',
        'surveillance:type': 'ALPR',
        'manufacturer': 'Flock Safety',
      },
      submittable: true,
      requiresDirection: true,
      fov: 90,
    );

NodeProfile _omniProfile() => NodeProfile(
      id: 'omni',
      name: 'Omni',
      tags: const {
        'man_made': 'surveillance',
      },
      submittable: true,
      requiresDirection: true,
      fov: 360,
    );

OperatorProfile _operatorProfile() => OperatorProfile(
      id: 'lowes',
      name: "Lowe's",
      tags: const {'operator': "Lowe's"},
    );

OsmNode _testNode() => OsmNode(
      id: 42,
      coord: const LatLng(40.0, -75.0),
      tags: const {
        'man_made': 'surveillance',
        'surveillance': 'public',
        'surveillance:type': 'ALPR',
        'manufacturer': 'Flock Safety',
        'direction': '90',
      },
    );

OsmNode _constrainedNode() => OsmNode(
      id: 44,
      coord: const LatLng(40.0, -75.0),
      tags: const {
        'man_made': 'surveillance',
        'surveillance:type': 'ALPR',
        'direction': '180',
      },
      isConstrained: true,
    );

/// Create an AddNodeSession ready for commit.
AddNodeSession _committedAddSession({
  List<double>? directions,
  NodeProfile? profile,
}) {
  final p = profile ?? _flockProfile();
  final session = AddNodeSession(
    profile: p,
    target: const LatLng(40.0, -75.0),
    changesetComment: 'Add Flock surveillance node',
  );
  if (directions != null) {
    session.directions
      ..clear()
      ..addAll(directions);
  }
  return session;
}

/// Create an EditNodeSession ready for commit.
EditNodeSession _committedEditSession({
  bool extractFromWay = false,
  bool isConstrained = false,
  List<double>? directions,
  NodeProfile? profile,
  LatLng? target,
}) {
  final node = isConstrained ? _constrainedNode() : _testNode();
  final p = profile ?? _flockProfile();
  final session = EditNodeSession(
    originalNode: node,
    originalHadDirections: true,
    profile: p,
    initialDirection: 90,
    target: target ?? const LatLng(40.1, -74.9),
    extractFromWay: extractFromWay,
    changesetComment: 'Update Flock surveillance node',
  );
  if (directions != null) {
    session.directions
      ..clear()
      ..addAll(directions);
  }
  return session;
}

/// Create a queue state with mocks.
UploadQueueState _createQueue({
  MockMapDataProvider? mockCache,
  MockNodeProviderWithCache? mockProvider,
}) {
  final cache = mockCache ?? MockMapDataProvider();
  final provider = mockProvider ?? MockNodeProviderWithCache();
  // Void methods are auto-stubbed by mocktail — no explicit stubs needed.
  return UploadQueueState(nodeCache: cache, nodeProvider: provider);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Ensure Flutter binding is initialized for SharedPreferences
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Set up empty SharedPreferences for each test
    SharedPreferences.setMockInitialValues({});
  });

  // =========================================================================
  // addFromSession
  // =========================================================================
  group('addFromSession', () {
    test('creates PendingUpload with create operation', () {
      final q = _createQueue();
      final session = _committedAddSession();

      q.addFromSession(session, uploadMode: UploadMode.simulate);

      expect(q.pendingCount, equals(1));
      expect(q.pendingUploads.first.operation, equals(UploadOperation.create));
      expect(q.pendingUploads.first.coord, equals(session.target));
    });

    test('adds temp node with negative ID and _pending_upload tag to cache', () {
      final mockCache = MockMapDataProvider();
      final mockProvider = MockNodeProviderWithCache();
      when(() => mockCache.addOrUpdate(any())).thenReturn(null);
      when(() => mockProvider.notifyListeners()).thenReturn(null);

      final q = UploadQueueState(nodeCache: mockCache, nodeProvider: mockProvider);
      final session = _committedAddSession();

      q.addFromSession(session, uploadMode: UploadMode.simulate);

      final captured = verify(() => mockCache.addOrUpdate(captureAny())).captured;
      expect(captured, hasLength(1));
      final nodes = captured.first as List<OsmNode>;
      expect(nodes, hasLength(1));
      expect(nodes.first.id, isNegative);
      expect(nodes.first.tags['_pending_upload'], equals('true'));
    });

    test('direction is stored as double for single direction', () {
      final q = _createQueue();
      final session = _committedAddSession(directions: [180.0]);

      q.addFromSession(session, uploadMode: UploadMode.simulate);

      expect(q.pendingUploads.first.direction, equals(180.0));
    });

    test('notifies listeners', () {
      final q = _createQueue();
      int count = 0;
      q.addListener(() => count++);

      q.addFromSession(_committedAddSession(), uploadMode: UploadMode.simulate);

      expect(count, equals(1));
    });
  });

  // =========================================================================
  // addFromEditSession
  // =========================================================================
  group('addFromEditSession', () {
    test('modify: creates edit operation with original node ID', () {
      final q = _createQueue();
      final session = _committedEditSession();

      q.addFromEditSession(session, uploadMode: UploadMode.simulate);

      expect(q.pendingCount, equals(1));
      expect(q.pendingUploads.first.operation, equals(UploadOperation.modify));
      expect(q.pendingUploads.first.originalNodeId, equals(42));
    });

    test('modify: marks original with _pending_edit and creates temp node', () {
      final mockCache = MockMapDataProvider();
      final mockProvider = MockNodeProviderWithCache();
      when(() => mockCache.addOrUpdate(any())).thenReturn(null);
      when(() => mockProvider.notifyListeners()).thenReturn(null);

      final q = UploadQueueState(nodeCache: mockCache, nodeProvider: mockProvider);
      final session = _committedEditSession();

      q.addFromEditSession(session, uploadMode: UploadMode.simulate);

      final captured = verify(() => mockCache.addOrUpdate(captureAny())).captured;
      expect(captured, hasLength(1));
      final nodes = captured.first as List<OsmNode>;
      // Should have 2 nodes: original with _pending_edit + temp node with _pending_upload
      expect(nodes, hasLength(2));

      final originalNode = nodes.firstWhere((n) => n.id == 42);
      expect(originalNode.tags['_pending_edit'], equals('true'));

      final tempNode = nodes.firstWhere((n) => n.id != 42);
      expect(tempNode.id, isNegative);
      expect(tempNode.tags['_pending_upload'], equals('true'));
      expect(tempNode.tags['_original_node_id'], equals('42'));
    });

    test('extract: creates only temp node (no _pending_edit on original)', () {
      final mockCache = MockMapDataProvider();
      final mockProvider = MockNodeProviderWithCache();
      when(() => mockCache.addOrUpdate(any())).thenReturn(null);
      when(() => mockProvider.notifyListeners()).thenReturn(null);

      final q = UploadQueueState(nodeCache: mockCache, nodeProvider: mockProvider);
      final session = _committedEditSession(
        extractFromWay: true,
        isConstrained: true,
      );

      q.addFromEditSession(session, uploadMode: UploadMode.simulate);

      expect(q.pendingUploads.first.operation, equals(UploadOperation.extract));

      final captured = verify(() => mockCache.addOrUpdate(captureAny())).captured;
      final nodes = captured.first as List<OsmNode>;
      // Should have 1 node: only the extracted temp node
      expect(nodes, hasLength(1));
      expect(nodes.first.id, isNegative);
      expect(nodes.first.tags['_pending_upload'], equals('true'));
    });

    test('constrained modify uses original coordinates', () {
      final q = _createQueue();
      final session = _committedEditSession(
        isConstrained: true,
        target: const LatLng(99.0, -99.0), // Different from node's coord
      );

      q.addFromEditSession(session, uploadMode: UploadMode.simulate);

      // Should use original node coord (40.0, -75.0) not the session target
      expect(q.pendingUploads.first.coord.latitude, equals(40.0));
      expect(q.pendingUploads.first.coord.longitude, equals(-75.0));
    });
  });

  // =========================================================================
  // addFromNodeDeletion
  // =========================================================================
  group('addFromNodeDeletion', () {
    test('creates delete operation and marks node with _pending_deletion', () {
      final mockCache = MockMapDataProvider();
      final mockProvider = MockNodeProviderWithCache();
      when(() => mockCache.addOrUpdate(any())).thenReturn(null);
      when(() => mockProvider.notifyListeners()).thenReturn(null);

      final q = UploadQueueState(nodeCache: mockCache, nodeProvider: mockProvider);
      final node = _testNode();

      q.addFromNodeDeletion(node, uploadMode: UploadMode.simulate);

      expect(q.pendingCount, equals(1));
      expect(q.pendingUploads.first.operation, equals(UploadOperation.delete));
      expect(q.pendingUploads.first.originalNodeId, equals(42));

      final captured = verify(() => mockCache.addOrUpdate(captureAny())).captured;
      final nodes = captured.first as List<OsmNode>;
      expect(nodes, hasLength(1));
      expect(nodes.first.id, equals(42));
      expect(nodes.first.tags['_pending_deletion'], equals('true'));
    });
  });

  // =========================================================================
  // clearQueue / removeFromQueue
  // =========================================================================
  group('clearQueue / removeFromQueue', () {
    test('clearQueue removes all items and cleans up cache for creates', () {
      final mockCache = MockMapDataProvider();
      final mockProvider = MockNodeProviderWithCache();
      when(() => mockCache.addOrUpdate(any())).thenReturn(null);
      when(() => mockCache.removeTempNodeById(any())).thenReturn(null);
      when(() => mockProvider.notifyListeners()).thenReturn(null);

      final q = UploadQueueState(nodeCache: mockCache, nodeProvider: mockProvider);
      q.addFromSession(_committedAddSession(), uploadMode: UploadMode.simulate);
      q.addFromSession(_committedAddSession(), uploadMode: UploadMode.simulate);
      expect(q.pendingCount, equals(2));

      q.clearQueue();
      expect(q.pendingCount, equals(0));
      // Each create upload should have removeTempNodeById called
      verify(() => mockCache.removeTempNodeById(any())).called(2);
    });

    test('clearQueue for edits removes temp + pending_edit marker', () {
      final mockCache = MockMapDataProvider();
      final mockProvider = MockNodeProviderWithCache();
      when(() => mockCache.addOrUpdate(any())).thenReturn(null);
      when(() => mockCache.removeTempNodeById(any())).thenReturn(null);
      when(() => mockCache.removePendingEditMarker(any())).thenReturn(null);
      when(() => mockProvider.notifyListeners()).thenReturn(null);

      final q = UploadQueueState(nodeCache: mockCache, nodeProvider: mockProvider);
      q.addFromEditSession(_committedEditSession(), uploadMode: UploadMode.simulate);

      q.clearQueue();
      verify(() => mockCache.removeTempNodeById(any())).called(1);
      verify(() => mockCache.removePendingEditMarker(42)).called(1);
    });

    test('clearQueue for deletions removes pending_deletion marker', () {
      final mockCache = MockMapDataProvider();
      final mockProvider = MockNodeProviderWithCache();
      when(() => mockCache.addOrUpdate(any())).thenReturn(null);
      when(() => mockCache.removePendingDeletionMarker(any())).thenReturn(null);
      when(() => mockProvider.notifyListeners()).thenReturn(null);

      final q = UploadQueueState(nodeCache: mockCache, nodeProvider: mockProvider);
      q.addFromNodeDeletion(_testNode(), uploadMode: UploadMode.simulate);

      q.clearQueue();
      verify(() => mockCache.removePendingDeletionMarker(42)).called(1);
    });

    test('clearQueue for extracts removes temp only (no pending_edit)', () {
      final mockCache = MockMapDataProvider();
      final mockProvider = MockNodeProviderWithCache();
      when(() => mockCache.addOrUpdate(any())).thenReturn(null);
      when(() => mockCache.removeTempNodeById(any())).thenReturn(null);
      when(() => mockProvider.notifyListeners()).thenReturn(null);

      final q = UploadQueueState(nodeCache: mockCache, nodeProvider: mockProvider);
      q.addFromEditSession(
        _committedEditSession(extractFromWay: true, isConstrained: true),
        uploadMode: UploadMode.simulate,
      );

      q.clearQueue();
      verify(() => mockCache.removeTempNodeById(any())).called(1);
      verifyNever(() => mockCache.removePendingEditMarker(any()));
    });

    test('removeFromQueue removes specific item', () {
      final q = _createQueue();
      q.addFromSession(_committedAddSession(), uploadMode: UploadMode.simulate);
      q.addFromSession(_committedAddSession(), uploadMode: UploadMode.simulate);
      expect(q.pendingCount, equals(2));

      final first = q.pendingUploads.first;
      q.removeFromQueue(first);
      expect(q.pendingCount, equals(1));
    });

    test('clearQueue notifies listeners', () {
      final q = _createQueue();
      q.addFromSession(_committedAddSession(), uploadMode: UploadMode.simulate);
      int count = 0;
      q.addListener(() => count++);

      q.clearQueue();
      expect(count, equals(1));
    });
  });

  // =========================================================================
  // Direction formatting
  // =========================================================================
  group('Direction formatting', () {
    test('single direction stored as double', () {
      final q = _createQueue();
      q.addFromSession(
        _committedAddSession(directions: [180.0]),
        uploadMode: UploadMode.simulate,
      );

      expect(q.pendingUploads.first.direction, equals(180.0));
    });

    test('multiple directions stored as semicolon-separated string', () {
      final q = _createQueue();
      q.addFromSession(
        _committedAddSession(directions: [90.0, 180.0, 270.0]),
        uploadMode: UploadMode.simulate,
      );

      expect(q.pendingUploads.first.direction, equals('90;180;270'));
    });

    test('FOV range notation: 180° center + 90° FOV = "135-225"', () {
      final q = _createQueue();
      q.addFromSession(
        _committedAddSession(
          directions: [180.0],
          profile: _flockProfileWithFov(),
        ),
        uploadMode: UploadMode.simulate,
      );

      expect(q.pendingUploads.first.direction, equals('135-225'));
    });

    test('FOV range notation: multiple directions with FOV', () {
      final q = _createQueue();
      q.addFromSession(
        _committedAddSession(
          directions: [90.0, 270.0],
          profile: _flockProfileWithFov(),
        ),
        uploadMode: UploadMode.simulate,
      );

      expect(q.pendingUploads.first.direction, equals('45-135;225-315'));
    });

    test('360° FOV = "0-360"', () {
      final q = _createQueue();
      q.addFromSession(
        _committedAddSession(
          directions: [180.0],
          profile: _omniProfile(),
        ),
        uploadMode: UploadMode.simulate,
      );

      expect(q.pendingUploads.first.direction, equals('0-360'));
    });

    test('FOV wrapping: 350° center + 90° FOV = "305-35"', () {
      final q = _createQueue();
      q.addFromSession(
        _committedAddSession(
          directions: [350.0],
          profile: _flockProfileWithFov(),
        ),
        uploadMode: UploadMode.simulate,
      );

      expect(q.pendingUploads.first.direction, equals('305-35'));
    });

    test('empty directions returns 0.0', () {
      final q = _createQueue();
      final session = _committedAddSession();
      session.directions.clear();

      q.addFromSession(session, uploadMode: UploadMode.simulate);

      expect(q.pendingUploads.first.direction, equals(0.0));
    });
  });

  // =========================================================================
  // Queue persistence
  // =========================================================================
  group('Queue persistence', () {
    test('save and load round-trip via SharedPreferences', () async {
      final q1 = _createQueue();
      q1.addFromSession(_committedAddSession(), uploadMode: UploadMode.simulate);
      q1.addFromSession(
        _committedAddSession(directions: [90.0, 180.0]),
        uploadMode: UploadMode.simulate,
      );
      expect(q1.pendingCount, equals(2));

      // Allow async _saveQueue to complete
      await Future<void>.delayed(Duration.zero);

      // Create a new queue instance and load from storage
      final q2 = _createQueue();
      await q2.init();

      expect(q2.pendingCount, equals(2));
      expect(q2.pendingUploads[0].operation, equals(UploadOperation.create));
      expect(q2.pendingUploads[1].operation, equals(UploadOperation.create));
    });

    test('edit operations persist originalNodeId', () async {
      final q1 = _createQueue();
      q1.addFromEditSession(_committedEditSession(), uploadMode: UploadMode.simulate);

      // Allow async _saveQueue to complete
      await Future<void>.delayed(Duration.zero);

      final q2 = _createQueue();
      await q2.init();

      expect(q2.pendingCount, equals(1));
      expect(q2.pendingUploads.first.operation, equals(UploadOperation.modify));
      expect(q2.pendingUploads.first.originalNodeId, equals(42));
    });

    test('clearQueue persists empty queue', () async {
      final q1 = _createQueue();
      q1.addFromSession(_committedAddSession(), uploadMode: UploadMode.simulate);
      q1.clearQueue();

      // Allow async _saveQueue to complete
      await Future<void>.delayed(Duration.zero);

      final q2 = _createQueue();
      await q2.init();

      expect(q2.pendingCount, equals(0));
    });
  });

  // =========================================================================
  // retryUpload
  // =========================================================================
  group('retryUpload', () {
    test('resets error state and attempts', () {
      final q = _createQueue();
      q.addFromSession(_committedAddSession(), uploadMode: UploadMode.simulate);

      final upload = q.pendingUploads.first;
      upload.setError('test error');
      upload.attempts = 3;

      q.retryUpload(upload);

      expect(upload.uploadState, equals(UploadState.pending));
      expect(upload.attempts, equals(0));
      expect(upload.errorMessage, isNull);
    });

    test('retryUpload notifies listeners', () {
      final q = _createQueue();
      q.addFromSession(_committedAddSession(), uploadMode: UploadMode.simulate);
      int count = 0;
      q.addListener(() => count++);

      q.retryUpload(q.pendingUploads.first);
      expect(count, equals(1));
    });
  });
}
