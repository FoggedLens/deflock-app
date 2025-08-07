import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../app_state.dart';
import '../models/camera_profile.dart';
import 'profile_editor.dart';
import '../services/offline_area_service.dart';

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
          // 1. Authentication section
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
                : const Text('Required to submit camera data'),
            onTap: () async {
              if (appState.isLoggedIn) {
                await appState.logout();
              } else {
                await appState.forceLogin(); // Use force login as the primary method
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(appState.isLoggedIn
                        ? 'Logged in as ${appState.username}'
                        : 'Logged out'),
                    backgroundColor: appState.isLoggedIn ? Colors.green : Colors.grey,
                  ),
                );
              }
            },
          ),
          // 1.5 Test connection (only when logged in)
          if (appState.isLoggedIn)
            ListTile(
              leading: const Icon(Icons.wifi_protected_setup),
              title: const Text('Test Connection'),
              subtitle: const Text('Verify OSM credentials are working'),
              onTap: () async {
                final isValid = await appState.validateToken();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isValid
                          ? 'Connection OK - credentials are valid'
                          : 'Connection failed - please re-login'),
                      backgroundColor: isValid ? Colors.green : Colors.red,
                    ),
                  );
                }
                if (!isValid) {
                  // Auto-logout if token is invalid
                  await appState.logout();
                }
              },
            ),
          const Divider(),
          // 2. Upload mode selector
          ListTile(
            leading: const Icon(Icons.cloud_upload),
            title: const Text('Upload Destination'),
            subtitle: const Text('Choose where cameras are uploaded'),
            trailing: DropdownButton<UploadMode>(
              value: appState.uploadMode,
              items: const [
                DropdownMenuItem(
                  value: UploadMode.production,
                  child: Text('Production'),
                ),
                DropdownMenuItem(
                  value: UploadMode.sandbox,
                  child: Text('Sandbox'),
                ),
                DropdownMenuItem(
                  value: UploadMode.simulate,
                  child: Text('Simulate'),
                ),
              ],
              onChanged: (mode) {
                if (mode != null) appState.setUploadMode(mode);
              },
            ),
          ),
          // Help text
          Padding(
            padding: const EdgeInsets.only(left: 56, top: 2, right: 16, bottom: 12),
            child: Builder(
              builder: (context) {
                switch (appState.uploadMode) {
                  case UploadMode.production:
                    return const Text('Upload to the live OSM database (visible to all users)', style: TextStyle(fontSize: 12, color: Colors.black87));
                  case UploadMode.sandbox:
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Uploads go to the OSM Sandbox (safe for testing, resets regularly).',
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'NOTE: Due to OpenStreetMap limitations, cameras submitted to the sandbox will NOT appear on the map in this app.',
                          style: TextStyle(fontSize: 11, color: Colors.redAccent),
                        ),
                      ],
                    );
                  case UploadMode.simulate:
                  default:
                    return const Text('Simulate uploads (does not contact OSM servers)', style: TextStyle(fontSize: 12, color: Colors.deepPurple));
                }
              },
            ),
          ),
          const Divider(),
          // 3. Queue management
          ListTile(
            leading: const Icon(Icons.queue),
            title: Text('Pending uploads: ${appState.pendingCount}'),
            subtitle: appState.uploadMode == UploadMode.simulate
                ? const Text('Simulate mode enabled – uploads simulated')
                : appState.uploadMode == UploadMode.sandbox
                    ? const Text('Sandbox mode – uploads go to OSM Sandbox')
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
          const Divider(),
          // 4. Camera Profiles
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Camera Profiles',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileEditor(
                      profile: CameraProfile(
                        id: const Uuid().v4(),
                        name: '',
                        tags: const {},
                      ),
                    ),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('New Profile'),
              ),
            ],
          ),
          ...appState.profiles.map(
            (p) => ListTile(
              leading: Checkbox(
                value: appState.isEnabled(p),
                onChanged: (v) => appState.toggleProfile(p, v ?? false),
              ),
              title: Text(p.name),
              subtitle: Text(p.builtin ? 'Built-in' : 'Custom'),
              trailing: p.builtin ? null : PopupMenuButton(
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: const Row(
                      children: [
                        Icon(Icons.edit),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: const Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) {
                  if (value == 'edit') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileEditor(profile: p),
                      ),
                    );
                  } else if (value == 'delete') {
                    _showDeleteProfileDialog(context, appState, p);
                  }
                },
              ),
            ),
          ),
          const Divider(),
          // 5. --- Offline Areas Section ---
          const Padding(
            padding: EdgeInsets.only(bottom: 8.0),
            child: Text('Offline Areas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          _OfflineAreasSection(),
          const Divider(),
          // 6. About/info button
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About / Info'),
            onTap: () async {
              // show dialog with text (replace with file contents as needed)
              showDialog(
                context: context,
                builder: (context) => FutureBuilder<String>(
                  future: DefaultAssetBundle.of(context).loadString('assets/info.txt'),
                  builder: (context, snapshot) => AlertDialog(
                    title: const Text('About This App'),
                    content: SingleChildScrollView(
                      child: Text(
                        snapshot.connectionState == ConnectionState.done
                          ? (snapshot.data ?? 'No info available.')
                          : 'Loading...',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showDeleteProfileDialog(BuildContext context, AppState appState, CameraProfile profile) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Profile'),
        content: Text('Are you sure you want to delete "${profile.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              appState.deleteProfile(profile);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Profile deleted')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
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

// --- Offline Areas UI section ---

class _OfflineAreasSection extends StatefulWidget {
  @override
  State<_OfflineAreasSection> createState() => _OfflineAreasSectionState();
}

class _OfflineAreasSectionState extends State<_OfflineAreasSection> {
  final OfflineAreaService service = OfflineAreaService();

  @override
  void initState() {
    super.initState();
    // Polling for now; can improve with ChangeNotifier or Streams pattern later.
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {});
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final areas = service.offlineAreas;
    if (areas.isEmpty) {
      return const ListTile(
        leading: Icon(Icons.download_for_offline),
        title: Text('No offline areas'),
        subtitle: Text('Download a map area for offline use.'),
      );
    }
    return Column(
      children: areas.map((area) {
        String diskStr = area.sizeBytes > 0
            ? area.sizeBytes > 1024 * 1024
                ? "${(area.sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB"
                : "${(area.sizeBytes / 1024).toStringAsFixed(1)} KB"
            : '--';
        String subtitle =
            'Z${area.minZoom}-${area.maxZoom}\n' +
                'Lat: ${area.bounds.southWest.latitude.toStringAsFixed(3)}, ${area.bounds.southWest.longitude.toStringAsFixed(3)}\n' +
                'Lat: ${area.bounds.northEast.latitude.toStringAsFixed(3)}, ${area.bounds.northEast.longitude.toStringAsFixed(3)}';
        subtitle += '\nTiles: ${area.tilesTotal}';
        subtitle += ' | Size: $diskStr';
        if (area.status == OfflineAreaStatus.complete) {
          subtitle += ' | Cameras: ${area.cameras.length}';
        }
        return Card(
          child: ListTile(
            leading: Icon(area.status == OfflineAreaStatus.complete
                ? Icons.cloud_done
                : area.status == OfflineAreaStatus.error
                    ? Icons.error
                    : Icons.download_for_offline),
            title: Row(
              children: [
                Expanded(
                  child: Text(area.name.isNotEmpty
                      ? area.name
                      : 'Area ${area.id.substring(0, 6)}...'),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: 'Rename area',
                  onPressed: () async {
                    String? newName = await showDialog<String>(
                      context: context,
                      builder: (ctx) {
                        final ctrl = TextEditingController(text: area.name);
                        return AlertDialog(
                          title: const Text('Rename Offline Area'),
                          content: TextField(
                            controller: ctrl,
                            maxLength: 40,
                            decoration: const InputDecoration(labelText: 'Area Name'),
                            autofocus: true,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(ctx, ctrl.text.trim());
                              },
                              child: const Text('Rename'),
                            ),
                          ],
                        );
                      },
                    );
                    if (newName != null && newName.trim().isNotEmpty) {
                      setState(() {
                        area.name = newName.trim();
                        service.saveAreasToDisk();
                      });
                    }
                  },
                ),
                if (area.status != OfflineAreaStatus.downloading)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: 'Delete offline area',
                    onPressed: () async {
                      service.deleteArea(area.id);
                      setState(() {});
                    },
                  ),
              ],
            ),
            subtitle: Text(subtitle),
            isThreeLine: true,
            trailing: area.status == OfflineAreaStatus.downloading
                ? SizedBox(
                    width: 64,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        LinearProgressIndicator(value: area.progress),
                        Text(
                          '${(area.progress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 12),
                        )
                      ],
                    ),
                  )
                : null,
            onLongPress: area.status == OfflineAreaStatus.downloading
                ? () {
                    service.cancelDownload(area.id);
                    setState(() {});
                  }
                : null,
          ),
        );
      }).toList(),
    );
  }
}
