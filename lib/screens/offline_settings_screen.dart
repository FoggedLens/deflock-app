import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import 'settings/sections/enable_offline_features_section.dart';
import 'settings/sections/offline_mode_section.dart';
import 'settings/sections/offline_areas_section.dart';
import '../services/localization_service.dart';

class OfflineSettingsScreen extends StatelessWidget {
  const OfflineSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final locService = LocalizationService.instance;
    
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) => Scaffold(
        appBar: AppBar(
          title: Text(locService.t('settings.offlineSettings')),
        ),
        body: Consumer<AppState>(
          builder: (context, appState, child) {
            final offlineFeaturesEnabled = appState.offlineFeaturesEnabled;

            return ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                const EnableOfflineFeaturesSection(),
                const Divider(),
                // Grey out and disable interaction with the rest of the
                // offline settings when the master toggle is off, while
                // keeping them visible/discoverable.
                Opacity(
                  opacity: offlineFeaturesEnabled ? 1.0 : 0.4,
                  child: IgnorePointer(
                    ignoring: !offlineFeaturesEnabled,
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OfflineModeSection(),
                        Divider(),
                        OfflineAreasSection(),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
