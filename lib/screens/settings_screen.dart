import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Logged in to OSM (OAuth – coming soon)'),
            value: appState.isLoggedIn,
            onChanged: null, // disabled for now
          ),
          const Divider(),
          const Text('Camera Profiles',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ...appState.profiles.map(
            (p) => SwitchListTile(
              title: Text(p.name),
              value: appState.isEnabled(p),
              onChanged: (v) => appState.toggleProfile(p, v),
            ),
          ),
        ],
      ),
    );
  }
}

