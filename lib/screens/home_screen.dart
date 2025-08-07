import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/map_view.dart';
import 'package:flutter_map/flutter_map.dart';
import '../services/offline_area_service.dart';
import '../widgets/add_camera_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final MapController _mapController = MapController();
  bool _followMe = true;

  void _openAddCameraSheet() {
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

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Flock Map'),
        actions: [
          IconButton(
            tooltip: _followMe ? 'Disable follow‑me' : 'Enable follow‑me',
            icon: Icon(_followMe ? Icons.gps_fixed : Icons.gps_off),
            onPressed: () => setState(() => _followMe = !_followMe),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: MapView(
        controller: _mapController,
        followMe: _followMe,
        onUserGesture: () {
          if (_followMe) setState(() => _followMe = false);
        },
      ),
      floatingActionButton: appState.session == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  onPressed: _openAddCameraSheet,
                  icon: const Icon(Icons.add_location_alt),
                  label: const Text('Tag Camera'),
                  heroTag: 'tag_camera_fab',
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (ctx) => DownloadAreaDialog(controller: _mapController),
                  ),
                  icon: const Icon(Icons.download_for_offline),
                  label: const Text('Download'),
                  heroTag: 'download_fab',
                ),
              ],
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

// --- Download area dialog ---
class DownloadAreaDialog extends StatefulWidget {
  final MapController controller;
  const DownloadAreaDialog({super.key, required this.controller});

  @override
  State<DownloadAreaDialog> createState() => _DownloadAreaDialogState();
}

class _DownloadAreaDialogState extends State<DownloadAreaDialog> {
  double _zoom = 15;

  // Fake estimation: about 0.5 MB per zoom per km² for now
  String get _storageEstimate {
    // This can be improved later to use map bounds
    final estMb = (0.5 * (_zoom - 11)).clamp(1, 50);
    return 'Est: ${estMb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: const [
          Icon(Icons.download_for_offline),
          SizedBox(width: 10),
          Text("Download Map Area"),
        ],
      ),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Max zoom level'),
                Text('Z${_zoom.toStringAsFixed(0)}'),
              ],
            ),
            Slider(
              min: 12,
              max: 19,
              divisions: 7,
              label: 'Z${_zoom.toStringAsFixed(0)}',
              value: _zoom,
              onChanged: (v) => setState(() => _zoom = v),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Storage estimate:'),
                Text(_storageEstimate),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            try {
              final bounds = widget.controller.camera.visibleBounds;
              final maxZoom = _zoom.toInt();
              final minZoom = _findDynamicMinZoom(bounds);
              final id = DateTime.now().toIso8601String().replaceAll(':', '-');
              final dir = '/tmp/offline_areas/$id';

              await OfflineAreaService().downloadArea(
                id: id,
                bounds: bounds,
                minZoom: minZoom,
                maxZoom: maxZoom,
                directory: dir,
                onProgress: (progress) {},
                onComplete: (status) {},
              );
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Download started!'),
                ),
              );
            } catch (e) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to start download: $e'),
                ),
              );
            }
          },
          child: const Text('Download'),
        ),
      ],
    );
  }

  int _findDynamicMinZoom(LatLngBounds bounds) {
    // For now, just pick 12 as min; can implement dynamic min‑zoom by area
    return 12;
  }
}

