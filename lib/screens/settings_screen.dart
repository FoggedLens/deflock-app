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
                ? 'Logged in as ${appState.username}'
                : 'Log in to OpenStreetMap'),
            subtitle: appState.isLoggedIn 
                ? const Text('Tap to logout')
                : const Text('Tap to login'),
            onTap: () async {
              if (appState.isLoggedIn) {
                await appState.logout();
              } else {
                await appState.login();
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Refresh Login Status'),
            subtitle: const Text('Check if you\'re already logged in'),
            onTap: () async {
              await appState.refreshAuthState();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(appState.isLoggedIn 
                        ? 'Logged in as ${appState.username}'
                        : 'Not logged in'),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.login_outlined),
            title: const Text('Force Fresh Login'),
            subtitle: const Text('Clear stored tokens and login again'),
            onTap: () async {
              await appState.forceLogin();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(appState.isLoggedIn 
                        ? 'Fresh login successful: ${appState.username}'
                        : 'Fresh login failed'),
                    backgroundColor: appState.isLoggedIn ? Colors.green : Colors.red,
                  ),
                );
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
          // Test mode toggle
          SwitchListTile(
            secondary: const Icon(Icons.bug_report),
            title: const Text('Test Mode'),
            subtitle: const Text('Simulate uploads without sending to OSM'),
            value: appState.testMode,
            onChanged: (value) => appState.setTestMode(value),
          ),
          const Divider(),
          // Queue management
          ListTile(
            leading: const Icon(Icons.queue),
            title: Text('Pending uploads: ${appState.pendingCount}'),
            subtitle: appState.testMode 
                ? const Text('Test mode enabled - uploads simulated')
                : const Text('Tap to view queue'),
            onTap: appState.pendingCount > 0 ? () {
              _showQueueDialog(context, appState);
            } : null,
          ),
          if (appState.pendingCount > 0)
            ListTile(
              leading: const Icon(Icons.clear_all),
              title: const Text('Clear Upload Queue'),
              subtitle: Text('Remove all ${appState.pendingCount} pending uploads'),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clear Queue'),
                    content: Text('Remove all ${appState.pendingCount} pending uploads?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          appState.clearQueue();
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Queue cleared')),
                          );
                        },
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showQueueDialog(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Upload Queue (${appState.pendingCount} items)'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: appState.pendingUploads.length,
            itemBuilder: (context, index) {
              final upload = appState.pendingUploads[index];
              return ListTile(
                leading: const Icon(Icons.camera_alt),
                title: Text('Camera ${index + 1}'),
                subtitle: Text(
                  'Lat: ${upload.coord.latitude.toStringAsFixed(6)}\n'
                  'Lon: ${upload.coord.longitude.toStringAsFixed(6)}\n'
                  'Direction: ${upload.direction.round()}°\n'
                  'Attempts: ${upload.attempts}'
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () {
                    appState.removeFromQueue(upload);
                    if (appState.pendingCount == 0) {
                      Navigator.pop(context);
                    }
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (appState.pendingCount > 1)
            TextButton(
              onPressed: () {
                appState.clearQueue();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Queue cleared')),
                );
              },
              child: const Text('Clear All'),
            ),
        ],
      ),
    );
  }
}

