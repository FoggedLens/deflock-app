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

NodeProfile _motorolaProfile() => NodeProfile(
      id: 'motorola',
      name: 'Motorola',
      tags: const {
        'man_made': 'surveillance',
        'surveillance': 'public',
        'surveillance:type': 'ALPR',
        'manufacturer': 'Motorola Solutions',
      },
      submittable: true,
      requiresDirection: true,
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
        'operator': "Lowe's",
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

List<NodeProfile> _enabledProfiles() => [_flockProfile(), _motorolaProfile()];
List<OperatorProfile> _operatorProfiles() => [_operatorProfile()];

/// Create a pair of (SessionState, UploadQueueState) with mock cache.
({SessionState session, UploadQueueState queue}) _createModules() {
  final mockCache = MockMapDataProvider();
  final mockProvider = MockNodeProviderWithCache();
  // Void methods are auto-stubbed by mocktail — no explicit stubs needed.

  return (
    session: SessionState(),
    queue: UploadQueueState(nodeCache: mockCache, nodeProvider: mockProvider),
  );
}

// ---------------------------------------------------------------------------
// Tests -- these replicate the method sequences AppState.commitSession() etc.
// execute, without needing the full AppState (which triggers heavy async init).
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // =========================================================================
  // Full add flow
  // =========================================================================
  group('Full add flow', () {
    test('startAddSession -> set target + profile -> commitSession -> addFromSession', () {
      final m = _createModules();
      final s = m.session;
      final q = m.queue;

      // 1. Start session
      s.startAddSession(_enabledProfiles());
      expect(s.session, isNotNull);

      // 2. Set target and profile
      s.updateSession(
        target: const LatLng(40.0, -75.0),
        profile: _flockProfile(),
      );

      // 3. Commit session (like AppState.commitSession)
      final committed = s.commitSession();
      expect(committed, isNotNull);
      expect(s.session, isNull);

      // 4. Add to queue (like AppState.commitSession does)
      q.addFromSession(committed!, uploadMode: UploadMode.simulate);
      expect(q.pendingCount, equals(1));
      expect(q.pendingUploads.first.operation, equals(UploadOperation.create));
    });
  });

  // =========================================================================
  // Full edit flow
  // =========================================================================
  group('Full edit flow', () {
    test('modify path: startEditSession -> update profile -> commitEditSession -> addFromEditSession', () {
      final m = _createModules();
      final s = m.session;
      final q = m.queue;

      // 1. Start edit session from existing node
      s.startEditSession(_testNode(), _enabledProfiles(), _operatorProfiles());
      expect(s.editSession, isNotNull);

      // 2. Change profile
      s.updateEditSession(profile: _flockProfile());

      // 3. Commit
      final committed = s.commitEditSession();
      expect(committed, isNotNull);
      expect(s.editSession, isNull);

      // 4. Add to queue
      q.addFromEditSession(committed!, uploadMode: UploadMode.simulate);
      expect(q.pendingCount, equals(1));
      expect(q.pendingUploads.first.operation, equals(UploadOperation.modify));
      expect(q.pendingUploads.first.originalNodeId, equals(42));
    });

    test('extract path: constrained node -> extractFromWay -> commit -> addFromEditSession', () {
      final m = _createModules();
      final s = m.session;
      final q = m.queue;

      // 1. Start edit session from constrained node
      s.startEditSession(_constrainedNode(), _enabledProfiles(), _operatorProfiles());

      // 2. Enable extract and move target
      s.updateEditSession(
        extractFromWay: true,
        target: const LatLng(41.0, -74.0),
        profile: _flockProfile(),
      );

      // 3. Commit
      final committed = s.commitEditSession();
      expect(committed, isNotNull);

      // 4. Add to queue
      q.addFromEditSession(committed!, uploadMode: UploadMode.simulate);
      expect(q.pendingCount, equals(1));
      expect(q.pendingUploads.first.operation, equals(UploadOperation.extract));
    });
  });

  // =========================================================================
  // Commit guards
  // =========================================================================
  group('Commit guards', () {
    test('incomplete session does not add to queue', () {
      final m = _createModules();
      final s = m.session;
      final q = m.queue;

      s.startAddSession(_enabledProfiles());
      // Only set profile, no target
      s.updateSession(profile: _flockProfile());

      final committed = s.commitSession();
      expect(committed, isNull);

      // Queue should remain empty
      expect(q.pendingCount, equals(0));
    });

    test('double commit is safe: second returns null and queue has only 1 item', () {
      final m = _createModules();
      final s = m.session;
      final q = m.queue;

      s.startAddSession(_enabledProfiles());
      s.updateSession(
        target: const LatLng(40.0, -75.0),
        profile: _flockProfile(),
      );

      // First commit succeeds
      final first = s.commitSession();
      expect(first, isNotNull);
      q.addFromSession(first!, uploadMode: UploadMode.simulate);

      // Second commit returns null
      final second = s.commitSession();
      expect(second, isNull);

      // Queue should have exactly 1 item
      expect(q.pendingCount, equals(1));
    });

    test('double edit commit is safe', () {
      final m = _createModules();
      final s = m.session;
      final q = m.queue;

      s.startEditSession(_testNode(), _enabledProfiles(), _operatorProfiles());

      final first = s.commitEditSession();
      expect(first, isNotNull);
      q.addFromEditSession(first!, uploadMode: UploadMode.simulate);

      final second = s.commitEditSession();
      expect(second, isNull);
      expect(q.pendingCount, equals(1));
    });
  });

  // =========================================================================
  // Profile deletion callback
  // =========================================================================
  group('Profile deletion callback', () {
    test('deleting profile used in active add session cancels that session', () {
      final m = _createModules();
      final s = m.session;

      s.startAddSession(_enabledProfiles());
      s.updateSession(profile: _flockProfile());
      expect(s.session?.profile?.id, equals('flock'));

      // Simulate what AppState._onProfileDeleted does
      if (s.session?.profile?.id == 'flock') {
        s.cancelSession();
      }

      expect(s.session, isNull);
    });

    test('deleting profile used in active edit session cancels that session', () {
      final m = _createModules();
      final s = m.session;

      s.startEditSession(_testNode(), _enabledProfiles(), _operatorProfiles());
      s.updateEditSession(profile: _flockProfile());
      expect(s.editSession?.profile?.id, equals('flock'));

      // Simulate what AppState._onProfileDeleted does
      if (s.editSession?.profile?.id == 'flock') {
        s.cancelEditSession();
      }

      expect(s.editSession, isNull);
    });

    test('deleting unrelated profile does not affect session', () {
      final m = _createModules();
      final s = m.session;

      s.startAddSession(_enabledProfiles());
      s.updateSession(profile: _flockProfile());

      // Simulate deleting a different profile
      final deletedProfile = _motorolaProfile();
      if (s.session?.profile?.id == deletedProfile.id) {
        s.cancelSession();
      }

      // Session should still be active with flock profile
      expect(s.session, isNotNull);
      expect(s.session!.profile!.id, equals('flock'));
    });

    test('deleting unrelated profile does not affect edit session', () {
      final m = _createModules();
      final s = m.session;

      s.startEditSession(_testNode(), _enabledProfiles(), _operatorProfiles());
      s.updateEditSession(profile: _flockProfile());

      final deletedProfile = _motorolaProfile();
      if (s.editSession?.profile?.id == deletedProfile.id) {
        s.cancelEditSession();
      }

      expect(s.editSession, isNotNull);
      expect(s.editSession!.profile!.id, equals('flock'));
    });
  });

  // =========================================================================
  // Notification propagation
  // =========================================================================
  group('Notification propagation', () {
    test('SessionState notifyListeners fires on add session operations', () {
      final s = SessionState();
      int count = 0;
      s.addListener(() => count++);

      s.startAddSession(_enabledProfiles());
      expect(count, equals(1));

      s.updateSession(target: const LatLng(40.0, -75.0));
      expect(count, equals(2));

      s.updateSession(profile: _flockProfile());
      expect(count, equals(3));

      s.commitSession();
      expect(count, equals(4));
    });

    test('SessionState notifyListeners fires on edit session operations', () {
      final s = SessionState();
      int count = 0;
      s.addListener(() => count++);

      s.startEditSession(_testNode(), _enabledProfiles(), _operatorProfiles());
      expect(count, equals(1));

      s.updateEditSession(profile: _flockProfile());
      expect(count, equals(2));

      s.commitEditSession();
      expect(count, equals(3));
    });

    test('UploadQueueState notifyListeners fires on queue operations', () {
      final m = _createModules();
      final q = m.queue;
      int count = 0;
      q.addListener(() => count++);

      final session = m.session;
      session.startAddSession(_enabledProfiles());
      session.updateSession(
        target: const LatLng(40.0, -75.0),
        profile: _flockProfile(),
      );
      final committed = session.commitSession();

      q.addFromSession(committed!, uploadMode: UploadMode.simulate);
      expect(count, equals(1));

      q.clearQueue();
      expect(count, equals(2));
    });
  });
}
