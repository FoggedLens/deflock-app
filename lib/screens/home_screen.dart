import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/map_view.dart';
import '../widgets/add_camera_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
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
        followMe: _followMe,
        onUserGesture: () {
          if (_followMe) setState(() => _followMe = false);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog(
          context: context,
          builder: (ctx) => const DownloadAreaDialog(),
        ),
        icon: const Icon(Icons.download_for_offline),
        label: const Text('Download'),
        heroTag: 'download_fab',
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      persistentFooterButtons: appState.session == null
          ? [
              FloatingActionButton.extended(
                onPressed: _openAddCameraSheet,
                icon: const Icon(Icons.add_location_alt),
                label: const Text('Tag Camera'),
                heroTag: 'tag_camera_fab',
              ),
            ]
          : null,
    );
  }
}

// --- Download area dialog ---

class DownloadAreaDialog extends StatefulWidget {
  const DownloadAreaDialog({super.key});

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
          onPressed: () {
            // Real download to be implemented in later stages.
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Download started (stub only)'),
              ),
            );
          },
          child: const Text('Download'),
        ),
      ],
    );
  }
}

