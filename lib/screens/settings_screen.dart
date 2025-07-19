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
          ListTile(
            leading: Icon(
              appState.isLoggedIn ? Icons.person : Icons.login,
              color: appState.isLoggedIn ? Colors.green : null,
            ),
            title: Text(appState.isLoggedIn
                ? 'Logged in as ${appState.username}'
                : 'Log in to OpenStreetMap'),
            onTap: () async {
              if (appState.isLoggedIn) {
                await appState.logout();
              } else {
                await appState.login();
              }
            },
          ),
          if (appState.isLoggedIn)
            ListTile(
              leading: const Icon(Icons.cloud_upload),
              title: const Text('Test upload'),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Upload will run soon...')),
              ),
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
          const Divider(),
          ListTile(
            leading: const Icon(Icons.sync),
            title: Text('Pending uploads: ${appState.pendingCount}'),
          ),
        ],
      ),
    );
  }
}

