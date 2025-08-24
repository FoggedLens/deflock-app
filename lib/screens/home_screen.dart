import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../dev_config.dart';
import '../widgets/map_view.dart';

import '../widgets/add_camera_sheet.dart';
import '../widgets/camera_provider_with_cache.dart';
import '../widgets/download_area_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<MapViewState> _mapViewKey = GlobalKey<MapViewState>();
  final MapController _mapController = MapController();
  bool _followMe = true;

  void _openAddCameraSheet() {
    // Disable follow-me when adding a camera so the map doesn't jump around
    setState(() => _followMe = false);
    
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
              tooltip: _followMe ? 'Disable follow‑me' : 'Enable follow‑me',
              icon: Icon(_followMe ? Icons.gps_fixed : Icons.gps_off),
              onPressed: () {
                setState(() => _followMe = !_followMe);
                // If enabling follow-me, retry location init in case permission was granted
                if (_followMe) {
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
              followMe: _followMe,
              onUserGesture: () {
                if (_followMe) setState(() => _followMe = false);
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

