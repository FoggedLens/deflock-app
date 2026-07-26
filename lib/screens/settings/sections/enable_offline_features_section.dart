import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app_state.dart';
import '../../../services/offline_area_service.dart';
import '../../../services/localization_service.dart';

/// Master toggle for all offline-area functionality (downloading, browsing,
/// and using cached tiles/nodes offline). When disabled, the rest of the
/// Offline Settings screen (offline mode + offline areas list) is greyed out
/// and the download button on the map screen is hidden. Functionally, the
/// app will behave as if no offline area data exists at all while this is
/// off, regardless of whether area files still exist on disk.
class EnableOfflineFeaturesSection extends StatelessWidget {
  const EnableOfflineFeaturesSection({super.key});

  Future<void> _handleToggle(BuildContext context, AppState appState, bool value) async {
    if (value) {
      // Enabling requires no confirmation.
      await appState.setOfflineFeaturesEnabled(true);
      return;
    }

    // Disabling: if offline area data already exists, ask whether to keep
    // or delete it. Either choice proceeds to disable the toggle - there is
    // no "cancel" path once this dialog is shown.
    final offlineService = OfflineAreaService();
    await offlineService.ensureInitialized();
    final hasExistingAreas = offlineService.offlineAreas.isNotEmpty;

    if (!hasExistingAreas) {
      await appState.setOfflineFeaturesEnabled(false);
      return;
    }

    final locService = LocalizationService.instance;
    final shouldDelete = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(locService.t('offlineAreas.disableConfirmTitle')),
        content: Text(locService.t('offlineAreas.disableConfirmMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(locService.t('offlineAreas.keepData')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(locService.t('offlineAreas.deleteData')),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      for (final area in offlineService.offlineAreas.toList()) {
        offlineService.deleteArea(area.id);
      }
    }

    // Disable regardless of the user's data choice.
    await appState.setOfflineFeaturesEnabled(false);
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
              locService.t('settings.enableOfflineFeatures'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(locService.t('settings.enableOfflineFeaturesTitle')),
              subtitle: Text(
                locService.t('settings.enableOfflineFeaturesSubtitle'),
                style: const TextStyle(fontSize: 12),
              ),
              value: appState.offlineFeaturesEnabled,
              onChanged: (value) => _handleToggle(context, appState, value),
            ),
          ],
        );
      },
    );
  }
}
