import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app_state.dart';
import '../../../services/offline_area_service.dart';
import '../../../services/localization_service.dart';

class OfflineModeSection extends StatelessWidget {
  const OfflineModeSection({super.key});

  Future<void> _handleOfflineModeChange(BuildContext context, AppState appState, bool value) async {
    final locService = LocalizationService.instance;
    
    // If enabling offline mode, check for active downloads
    if (value && !appState.offlineMode) {
      final offlineService = OfflineAreaService();
      if (offlineService.hasActiveDownloads) {
        // Show confirmation dialog
        final shouldProceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.warning, color: Colors.orange),
                const SizedBox(width: 8),
                Text(locService.t('settings.offlineModeWarningTitle')),
              ],
            ),
            content: Text(locService.t('settings.offlineModeWarningMessage')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(locService.cancel),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: Text(locService.t('settings.enableOfflineMode')),
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
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        final appState = context.watch<AppState>();
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              locService.t('settings.offlineMode'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.wifi_off),
              title: Text(locService.t('settings.offlineModeSubtitle')),
              trailing: Switch(
                value: appState.offlineMode,
                onChanged: (value) => _handleOfflineModeChange(context, appState, value),
              ),
            ),

          ],
        );
      },
    );
  }
}
