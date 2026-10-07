import 'dart:async';

import 'package:deflockapp/app_state.dart';
import 'package:deflockapp/models/node_profile.dart';
import 'package:deflockapp/models/osm_node.dart';
import 'package:deflockapp/services/node_data_manager.dart';
import 'package:deflockapp/widgets/add_node_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAppState extends Mock implements AppState {}

class _MockNodeDataManager extends Mock implements NodeDataManager {}

class _FakeLatLngBounds extends Fake implements LatLngBounds {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_FakeLatLngBounds());
    registerFallbackValue(const LatLng(0, 0));
    registerFallbackValue(UploadMode.production);
  });

  testWidgets(
    'uncovered target requests its area once and an empty success releases the loading gate',
    (tester) async {
      SharedPreferences.setMockInitialValues(const {
        'has_completed_positioning_tutorial': true,
      });

      final profile = NodeProfile(
        id: 'test-profile',
        name: 'Test profile',
        tags: const {'man_made': 'surveillance'},
      );
      const target = LatLng(38.8977, -77.0365);
      final session = AddNodeSession(profile: profile, target: target);
      final appState = _MockAppState();
      final nodeDataManager = _MockNodeDataManager();
      final response = Completer<List<OsmNode>>();
      VoidCallback? cacheListener;
      var covered = false;

      when(() => appState.enabledProfiles).thenReturn([profile]);
      when(() => appState.isLoggedIn).thenReturn(true);
      when(() => appState.uploadMode).thenReturn(UploadMode.production);
      when(() => appState.addListener(any())).thenReturn(null);
      when(() => appState.removeListener(any())).thenReturn(null);
      when(() => nodeDataManager.addListener(any())).thenAnswer((invocation) {
        cacheListener = invocation.positionalArguments.single as VoidCallback;
      });
      when(() => nodeDataManager.removeListener(any())).thenReturn(null);
      when(
        () => nodeDataManager.hasGoodCoverageFor(any()),
      ).thenAnswer((_) => covered);
      when(
        () => nodeDataManager.findNodesWithinDistance(any(), any()),
      ).thenReturn(const []);
      when(
        () => nodeDataManager.getNodesFor(
          bounds: any(named: 'bounds'),
          profiles: any(named: 'profiles'),
          uploadMode: any(named: 'uploadMode'),
          isUserInitiated: true,
        ),
      ).thenAnswer((_) => response.future);

      late StateSetter rebuildHost;
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  rebuildHost = setState;
                  return AddNodeSheet(
                    session: session,
                    nodeDataManager: nodeDataManager,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final request = verify(
        () => nodeDataManager.getNodesFor(
          bounds: captureAny(named: 'bounds'),
          profiles: captureAny(named: 'profiles'),
          uploadMode: captureAny(named: 'uploadMode'),
          isUserInitiated: true,
        ),
      );
      request.called(1);
      final captured = request.captured;
      final requestedBounds = captured[0] as LatLngBounds;
      expect(requestedBounds.south, closeTo(target.latitude - 0.001, 1e-9));
      expect(requestedBounds.north, closeTo(target.latitude + 0.001, 1e-9));
      expect(requestedBounds.west, closeTo(target.longitude - 0.001, 1e-9));
      expect(requestedBounds.east, closeTo(target.longitude + 0.001, 1e-9));
      expect(captured[1], same(appState.enabledProfiles));
      expect(captured[2], UploadMode.production);
      expect(find.byIcon(Icons.cloud_download), findsOneWidget);

      for (var i = 0; i < 3; i++) {
        rebuildHost(() {});
        await tester.pump();
      }
      verifyNever(
        () => nodeDataManager.getNodesFor(
          bounds: any(named: 'bounds'),
          profiles: any(named: 'profiles'),
          uploadMode: any(named: 'uploadMode'),
          isUserInitiated: true,
        ),
      );

      covered = true;
      response.complete(const []);
      await tester.pump();
      cacheListener?.call();
      await tester.pump();

      expect(
        find.byIcon(Icons.cloud_download),
        findsNothing,
        reason:
            'A successful empty response still proves the area was checked.',
      );
      final submitButton = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(submitButton.onPressed, isNotNull);

      rebuildHost(() {});
      await tester.pump();
      verifyNever(
        () => nodeDataManager.getNodesFor(
          bounds: any(named: 'bounds'),
          profiles: any(named: 'profiles'),
          uploadMode: any(named: 'uploadMode'),
          isUserInitiated: true,
        ),
      );
    },
  );

  testWidgets(
    'completed request without coverage retries after a cache rebuild',
    (tester) async {
      SharedPreferences.setMockInitialValues(const {
        'has_completed_positioning_tutorial': true,
      });

      final profile = NodeProfile(
        id: 'test-profile',
        name: 'Test profile',
        tags: const {'man_made': 'surveillance'},
      );
      const target = LatLng(38.8977, -77.0365);
      final session = AddNodeSession(profile: profile, target: target);
      final appState = _MockAppState();
      final nodeDataManager = _MockNodeDataManager();
      final response = Completer<List<OsmNode>>();
      VoidCallback? cacheListener;

      when(() => appState.enabledProfiles).thenReturn([profile]);
      when(() => appState.isLoggedIn).thenReturn(true);
      when(() => appState.uploadMode).thenReturn(UploadMode.production);
      when(() => appState.addListener(any())).thenReturn(null);
      when(() => appState.removeListener(any())).thenReturn(null);
      when(() => nodeDataManager.addListener(any())).thenAnswer((invocation) {
        cacheListener = invocation.positionalArguments.single as VoidCallback;
      });
      when(() => nodeDataManager.removeListener(any())).thenReturn(null);
      when(() => nodeDataManager.hasGoodCoverageFor(any())).thenReturn(false);
      when(
        () => nodeDataManager.findNodesWithinDistance(any(), any()),
      ).thenReturn(const []);
      when(
        () => nodeDataManager.getNodesFor(
          bounds: any(named: 'bounds'),
          profiles: any(named: 'profiles'),
          uploadMode: any(named: 'uploadMode'),
          isUserInitiated: true,
        ),
      ).thenAnswer((_) => response.future);

      late StateSetter rebuildHost;
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  rebuildHost = setState;
                  return AddNodeSheet(
                    session: session,
                    nodeDataManager: nodeDataManager,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      verify(
        () => nodeDataManager.getNodesFor(
          bounds: any(named: 'bounds'),
          profiles: any(named: 'profiles'),
          uploadMode: any(named: 'uploadMode'),
          isUserInitiated: true,
        ),
      ).called(1);

      response.complete(const []);
      await tester.pump();
      cacheListener?.call();
      rebuildHost(() {});
      await tester.pump();

      verify(
        () => nodeDataManager.getNodesFor(
          bounds: any(named: 'bounds'),
          profiles: any(named: 'profiles'),
          uploadMode: any(named: 'uploadMode'),
          isUserInitiated: true,
        ),
      ).called(1);
    },
  );

  testWidgets(
    'changing the selected profile does not duplicate an in-flight coverage request',
    (tester) async {
      SharedPreferences.setMockInitialValues(const {
        'has_completed_positioning_tutorial': true,
      });

      final firstProfile = NodeProfile(
        id: 'first-profile',
        name: 'First profile',
        tags: const {'man_made': 'surveillance'},
      );
      final secondProfile = NodeProfile(
        id: 'second-profile',
        name: 'Second profile',
        tags: const {'man_made': 'surveillance'},
      );
      const target = LatLng(38.8977, -77.0365);
      final session = AddNodeSession(profile: firstProfile, target: target);
      final appState = _MockAppState();
      final nodeDataManager = _MockNodeDataManager();
      final response = Completer<List<OsmNode>>();

      when(
        () => appState.enabledProfiles,
      ).thenReturn([firstProfile, secondProfile]);
      when(() => appState.isLoggedIn).thenReturn(true);
      when(() => appState.uploadMode).thenReturn(UploadMode.production);
      when(() => appState.addListener(any())).thenReturn(null);
      when(() => appState.removeListener(any())).thenReturn(null);
      when(() => nodeDataManager.addListener(any())).thenReturn(null);
      when(() => nodeDataManager.removeListener(any())).thenReturn(null);
      when(() => nodeDataManager.hasGoodCoverageFor(any())).thenReturn(false);
      when(
        () => nodeDataManager.findNodesWithinDistance(any(), any()),
      ).thenReturn(const []);
      when(
        () => nodeDataManager.getNodesFor(
          bounds: any(named: 'bounds'),
          profiles: any(named: 'profiles'),
          uploadMode: any(named: 'uploadMode'),
          isUserInitiated: true,
        ),
      ).thenAnswer((_) => response.future);

      late StateSetter rebuildHost;
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  rebuildHost = setState;
                  return AddNodeSheet(
                    session: session,
                    nodeDataManager: nodeDataManager,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      session.profile = secondProfile;
      rebuildHost(() {});
      await tester.pump();

      verify(
        () => nodeDataManager.getNodesFor(
          bounds: any(named: 'bounds'),
          profiles: any(named: 'profiles'),
          uploadMode: any(named: 'uploadMode'),
          isUserInitiated: true,
        ),
      ).called(1);
    },
  );

  testWidgets(
    'queued coverage request stays with the manager that scheduled it',
    (tester) async {
      SharedPreferences.setMockInitialValues(const {
        'has_completed_positioning_tutorial': true,
      });

      final profile = NodeProfile(
        id: 'test-profile',
        name: 'Test profile',
        tags: const {'man_made': 'surveillance'},
      );
      const target = LatLng(38.8977, -77.0365);
      final session = AddNodeSession(profile: profile, target: target);
      final appState = _MockAppState();
      final originalManager = _MockNodeDataManager();
      final replacementManager = _MockNodeDataManager();
      final originalResponse = Completer<List<OsmNode>>();
      final replacementResponse = Completer<List<OsmNode>>();
      final sheetKey = GlobalKey();
      var managerSwapped = false;

      when(() => appState.enabledProfiles).thenReturn([profile]);
      when(() => appState.isLoggedIn).thenReturn(true);
      when(() => appState.uploadMode).thenReturn(UploadMode.production);
      when(() => appState.addListener(any())).thenReturn(null);
      when(() => appState.removeListener(any())).thenReturn(null);
      for (final manager in [originalManager, replacementManager]) {
        when(() => manager.addListener(any())).thenReturn(null);
        when(() => manager.removeListener(any())).thenReturn(null);
        when(() => manager.hasGoodCoverageFor(any())).thenReturn(false);
        when(
          () => manager.findNodesWithinDistance(any(), any()),
        ).thenReturn(const []);
      }
      when(
        () => originalManager.getNodesFor(
          bounds: any(named: 'bounds'),
          profiles: any(named: 'profiles'),
          uploadMode: any(named: 'uploadMode'),
          isUserInitiated: true,
        ),
      ).thenAnswer((_) => originalResponse.future);
      when(
        () => replacementManager.getNodesFor(
          bounds: any(named: 'bounds'),
          profiles: any(named: 'profiles'),
          uploadMode: any(named: 'uploadMode'),
          isUserInitiated: true,
        ),
      ).thenAnswer((_) => replacementResponse.future);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  AddNodeSheet(
                    key: sheetKey,
                    session: session,
                    nodeDataManager: originalManager,
                  ),
                  Builder(
                    builder: (context) {
                      if (!managerSwapped) {
                        managerSwapped = true;
                        final element =
                            sheetKey.currentContext! as StatefulElement;
                        element.update(
                          AddNodeSheet(
                            key: sheetKey,
                            session: session,
                            nodeDataManager: replacementManager,
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      verify(
        () => originalManager.getNodesFor(
          bounds: any(named: 'bounds'),
          profiles: any(named: 'profiles'),
          uploadMode: any(named: 'uploadMode'),
          isUserInitiated: true,
        ),
      ).called(1);
    },
  );

  testWidgets(
    'coverage invalidation retries a successful sheet-owned request',
    (tester) async {
      SharedPreferences.setMockInitialValues(const {
        'has_completed_positioning_tutorial': true,
      });

      final profile = NodeProfile(
        id: 'test-profile',
        name: 'Test profile',
        tags: const {'man_made': 'surveillance'},
      );
      const target = LatLng(38.8977, -77.0365);
      final session = AddNodeSession(profile: profile, target: target);
      final appState = _MockAppState();
      final nodeDataManager = _MockNodeDataManager();
      final response = Completer<List<OsmNode>>();
      VoidCallback? cacheListener;
      var covered = false;

      when(() => appState.enabledProfiles).thenReturn([profile]);
      when(() => appState.isLoggedIn).thenReturn(true);
      when(() => appState.uploadMode).thenReturn(UploadMode.production);
      when(() => appState.addListener(any())).thenReturn(null);
      when(() => appState.removeListener(any())).thenReturn(null);
      when(() => nodeDataManager.addListener(any())).thenAnswer((invocation) {
        cacheListener = invocation.positionalArguments.single as VoidCallback;
      });
      when(() => nodeDataManager.removeListener(any())).thenReturn(null);
      when(
        () => nodeDataManager.hasGoodCoverageFor(any()),
      ).thenAnswer((_) => covered);
      when(
        () => nodeDataManager.findNodesWithinDistance(any(), any()),
      ).thenReturn(const []);
      when(
        () => nodeDataManager.getNodesFor(
          bounds: any(named: 'bounds'),
          profiles: any(named: 'profiles'),
          uploadMode: any(named: 'uploadMode'),
          isUserInitiated: true,
        ),
      ).thenAnswer((_) => response.future);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: Scaffold(
              body: AddNodeSheet(
                session: session,
                nodeDataManager: nodeDataManager,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      verify(
        () => nodeDataManager.getNodesFor(
          bounds: any(named: 'bounds'),
          profiles: any(named: 'profiles'),
          uploadMode: any(named: 'uploadMode'),
          isUserInitiated: true,
        ),
      ).called(1);

      covered = true;
      response.complete(const []);
      await tester.pump();
      cacheListener?.call();
      await tester.pump();
      expect(find.byIcon(Icons.cloud_download), findsNothing);

      covered = false;
      cacheListener?.call();
      await tester.pump();

      verify(
        () => nodeDataManager.getNodesFor(
          bounds: any(named: 'bounds'),
          profiles: any(named: 'profiles'),
          uploadMode: any(named: 'uploadMode'),
          isUserInitiated: true,
        ),
      ).called(1);
    },
  );

  testWidgets(
    'synchronous cache notification does not automatically retry after request completion',
    (tester) async {
      SharedPreferences.setMockInitialValues(const {
        'has_completed_positioning_tutorial': true,
      });

      final profile = NodeProfile(
        id: 'test-profile',
        name: 'Test profile',
        tags: const {'man_made': 'surveillance'},
      );
      const target = LatLng(38.8977, -77.0365);
      final session = AddNodeSession(profile: profile, target: target);
      final appState = _MockAppState();
      final nodeDataManager = _MockNodeDataManager();
      final firstResponse = Completer<List<OsmNode>>();
      final retryResponse = Completer<List<OsmNode>>();
      VoidCallback? cacheListener;
      var requestCount = 0;

      when(() => appState.enabledProfiles).thenReturn([profile]);
      when(() => appState.isLoggedIn).thenReturn(true);
      when(() => appState.uploadMode).thenReturn(UploadMode.production);
      when(() => appState.addListener(any())).thenReturn(null);
      when(() => appState.removeListener(any())).thenReturn(null);
      when(() => nodeDataManager.addListener(any())).thenAnswer((invocation) {
        cacheListener = invocation.positionalArguments.single as VoidCallback;
      });
      when(() => nodeDataManager.removeListener(any())).thenReturn(null);
      when(() => nodeDataManager.hasGoodCoverageFor(any())).thenReturn(false);
      when(
        () => nodeDataManager.findNodesWithinDistance(any(), any()),
      ).thenReturn(const []);
      when(
        () => nodeDataManager.getNodesFor(
          bounds: any(named: 'bounds'),
          profiles: any(named: 'profiles'),
          uploadMode: any(named: 'uploadMode'),
          isUserInitiated: true,
        ),
      ).thenAnswer((_) {
        requestCount++;
        if (requestCount == 1) {
          cacheListener?.call();
          return firstResponse.future;
        }
        return retryResponse.future;
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: Scaffold(
              body: AddNodeSheet(
                session: session,
                nodeDataManager: nodeDataManager,
              ),
            ),
          ),
        ),
      );
      expect(requestCount, 1);

      firstResponse.complete(const []);
      await tester.pump();
      await tester.pump();

      expect(
        requestCount,
        1,
        reason:
            'The cache rebuild was emitted by the request already in flight.',
      );
    },
  );

  testWidgets(
    'manager replacement recovers independently while queued work stays with original manager',
    (tester) async {
      SharedPreferences.setMockInitialValues(const {
        'has_completed_positioning_tutorial': true,
      });

      final profile = NodeProfile(
        id: 'test-profile',
        name: 'Test profile',
        tags: const {'man_made': 'surveillance'},
      );
      const target = LatLng(38.8977, -77.0365);
      final session = AddNodeSession(profile: profile, target: target);
      final appState = _MockAppState();
      final originalManager = _MockNodeDataManager();
      final replacementManager = _MockNodeDataManager();
      final originalResponse = Completer<List<OsmNode>>();
      final replacementResponse = Completer<List<OsmNode>>();
      final sheetKey = GlobalKey();
      var managerSwapped = false;

      when(() => appState.enabledProfiles).thenReturn([profile]);
      when(() => appState.isLoggedIn).thenReturn(true);
      when(() => appState.uploadMode).thenReturn(UploadMode.production);
      when(() => appState.addListener(any())).thenReturn(null);
      when(() => appState.removeListener(any())).thenReturn(null);
      for (final manager in [originalManager, replacementManager]) {
        when(() => manager.addListener(any())).thenReturn(null);
        when(() => manager.removeListener(any())).thenReturn(null);
        when(() => manager.hasGoodCoverageFor(any())).thenReturn(false);
        when(
          () => manager.findNodesWithinDistance(any(), any()),
        ).thenReturn(const []);
      }
      when(
        () => originalManager.getNodesFor(
          bounds: any(named: 'bounds'),
          profiles: any(named: 'profiles'),
          uploadMode: any(named: 'uploadMode'),
          isUserInitiated: true,
        ),
      ).thenAnswer((_) => originalResponse.future);
      when(
        () => replacementManager.getNodesFor(
          bounds: any(named: 'bounds'),
          profiles: any(named: 'profiles'),
          uploadMode: any(named: 'uploadMode'),
          isUserInitiated: true,
        ),
      ).thenAnswer((_) => replacementResponse.future);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  AddNodeSheet(
                    key: sheetKey,
                    session: session,
                    nodeDataManager: originalManager,
                  ),
                  Builder(
                    builder: (context) {
                      if (!managerSwapped) {
                        managerSwapped = true;
                        final element =
                            sheetKey.currentContext! as StatefulElement;
                        element.update(
                          AddNodeSheet(
                            key: sheetKey,
                            session: session,
                            nodeDataManager: replacementManager,
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      verify(
        () => originalManager.getNodesFor(
          bounds: any(named: 'bounds'),
          profiles: any(named: 'profiles'),
          uploadMode: any(named: 'uploadMode'),
          isUserInitiated: true,
        ),
      ).called(1);
      verify(
        () => replacementManager.getNodesFor(
          bounds: any(named: 'bounds'),
          profiles: any(named: 'profiles'),
          uploadMode: any(named: 'uploadMode'),
          isUserInitiated: true,
        ),
      ).called(1);
    },
  );
}
