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
  bool _followMe = true;

  Future<void> _startAddCamera(BuildContext context) async {
    final appState = context.read<AppState>();
    appState.startAddSession();

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      isDismissible: false,
      builder: (_) => const AddCameraSheet(),
    );

    if (submitted == true) {
      appState.commitSession();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Camera queued')));
      }
    } else {
      appState.cancelSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        onPressed: () => _startAddCamera(context),
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Tag Camera'),
      ),
    );
  }
}

