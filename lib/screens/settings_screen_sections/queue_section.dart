import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';

class QueueSection extends StatelessWidget {
  const QueueSection({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.queue),
          title: Text('Pending uploads: ${appState.pendingCount}'),
          subtitle: appState.uploadMode == UploadMode.simulate
              ? const Text('Simulate mode enabled – uploads simulated')
              : appState.uploadMode == UploadMode.sandbox
                  ? const Text('Sandbox mode – uploads go to OSM Sandbox')
                  : const Text('Tap to view queue'),
          onTap: appState.pendingCount > 0
              ? () => _showQueueDialog(context)
              : null,
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
    );
  }

  void _showQueueDialog(BuildContext context) {
    final appState = context.read<AppState>();
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
