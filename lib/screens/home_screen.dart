import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../dev_config.dart';
import '../widgets/map_view.dart';

import '../widgets/add_camera_sheet.dart';
import '../widgets/camera_provider_with_cache.dart';
import '../widgets/download_area_dialog.dart';

enum FollowMeMode {
  off,      // No following
  northUp,  // Follow position, keep north up
  rotating, // Follow position and rotation
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<MapViewState> _mapViewKey = GlobalKey<MapViewState>();
  final MapController _mapController = MapController();
  FollowMeMode _followMeMode = FollowMeMode.northUp;

  String _getFollowMeTooltip() {
    switch (_followMeMode) {
      case FollowMeMode.off:
        return 'Enable follow-me (north up)';
      case FollowMeMode.northUp:
        return 'Enable follow-me (rotating)';
      case FollowMeMode.rotating:
        return 'Disable follow-me';
    }
  }

  IconData _getFollowMeIcon() {
    switch (_followMeMode) {
      case FollowMeMode.off:
        return Icons.gps_off;
      case FollowMeMode.northUp:
        return Icons.gps_fixed;
      case FollowMeMode.rotating:
        return Icons.navigation;
    }
  }

  FollowMeMode _getNextFollowMeMode() {
    switch (_followMeMode) {
      case FollowMeMode.off:
        return FollowMeMode.northUp;
      case FollowMeMode.northUp:
        return FollowMeMode.rotating;
      case FollowMeMode.rotating:
        return FollowMeMode.off;
    }
  }

  void _openAddCameraSheet() {
    // Disable follow-me when adding a camera so the map doesn't jump around
    setState(() => _followMeMode = FollowMeMode.off);
    
    final appState = context.read<AppState>();
    appState.startAddSession();
    final session = appState.session!;          // guaranteed non‑null now

    _scaffoldKey.currentState!.showBottomSheet(
      (ctx) => AddCameraSheet(session: session),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CameraProviderWithCache>(create: (_) => CameraProviderWithCache()),
      ],
      child: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: const Text('Flock Map'),
          actions: [
            IconButton(
              tooltip: _getFollowMeTooltip(),
              icon: Icon(_getFollowMeIcon()),
              onPressed: () {
                setState(() {
                  final oldMode = _followMeMode;
                  _followMeMode = _getNextFollowMeMode();
                  debugPrint('[HomeScreen] Follow mode changed: $oldMode → $_followMeMode');
                });
                // If enabling follow-me, retry location init in case permission was granted
                if (_followMeMode != FollowMeMode.off) {
                  _mapViewKey.currentState?.retryLocationInit();
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.pushNamed(context, '/settings'),
            ),
          ],
        ),
        body: Stack(
          children: [
            MapView(
              key: _mapViewKey,
              controller: _mapController,
              followMeMode: _followMeMode,
              onUserGesture: () {
                if (_followMeMode != FollowMeMode.off) {
                  setState(() => _followMeMode = FollowMeMode.off);
                }
              },
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + kBottomButtonBarMargin,
                  left: 8,
                  right: 8,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
                  ),
                  margin: EdgeInsets.only(bottom: kBottomButtonBarMargin),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: Icon(Icons.add_location_alt),
                          label: Text('Tag Camera'),
                          onPressed: _openAddCameraSheet,
                          style: ElevatedButton.styleFrom(
                            minimumSize: Size(0, 48),
                            textStyle: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: Icon(Icons.download_for_offline),
                          label: Text('Download'),
                          onPressed: () => showDialog(
                            context: context,
                            builder: (ctx) => DownloadAreaDialog(controller: _mapController),
                          ),
                          style: ElevatedButton.styleFrom(
                            minimumSize: Size(0, 48),
                            textStyle: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

