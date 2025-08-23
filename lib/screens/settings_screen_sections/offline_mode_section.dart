import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../services/offline_area_service.dart';

class OfflineModeSection extends StatelessWidget {
  const OfflineModeSection({super.key});

  Future<void> _handleOfflineModeChange(BuildContext context, AppState appState, bool value) async {
    // If enabling offline mode, check for active downloads
    if (value && !appState.offlineMode) {
      final offlineService = OfflineAreaService();
      if (offlineService.hasActiveDownloads) {
        // Show confirmation dialog
        final shouldProceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.warning, color: Colors.orange),
                SizedBox(width: 8),
                Text('Active Downloads'),
              ],
            ),
            content: const Text(
              'Enabling offline mode will cancel any active area downloads. Do you want to continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Enable Offline Mode'),
              ),
            ],
          ),
        );
        
        if (shouldProceed != true) {
          return; // User cancelled
        }
      }
    }
    
    // Proceed with the change
    await appState.setOfflineMode(value);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return ListTile(
      leading: const Icon(Icons.wifi_off),
      title: const Text('Offline Mode'),
      subtitle: const Text('Disable all network requests except for local/offline areas.'),
      trailing: Switch(
        value: appState.offlineMode,
        onChanged: (value) => _handleOfflineModeChange(context, appState, value),
      ),
    );
  }
}
