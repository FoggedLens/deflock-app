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
      floatingActionButton: appState.session == null
          ? FloatingActionButton.extended(
              onPressed: _openAddCameraSheet,
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Tag Camera'),
            )
          : null,
    );
  }
}

