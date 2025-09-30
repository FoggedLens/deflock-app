import 'package:flutter/material.dart';
import 'settings_screen_sections/auth_section.dart';
import 'settings_screen_sections/upload_mode_section.dart';
import 'settings_screen_sections/profile_list_section.dart';
import 'settings_screen_sections/operator_profile_list_section.dart';
import 'settings_screen_sections/queue_section.dart';
import 'settings_screen_sections/offline_areas_section.dart';
import 'settings_screen_sections/offline_mode_section.dart';
import 'settings_screen_sections/about_section.dart';
import 'settings_screen_sections/max_nodes_section.dart';
import 'settings_screen_sections/proximity_alerts_section.dart';
import 'settings_screen_sections/tile_provider_section.dart';
import 'settings_screen_sections/language_section.dart';
import '../services/localization_service.dart';
import '../dev_config.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) => Scaffold(
        appBar: AppBar(title: Text(LocalizationService.instance.t('settings.title'))),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Only show upload mode section in development builds
            if (kEnableDevelopmentModes) ...[
              const UploadModeSection(),
              const Divider(),
            ],
            const AuthSection(),
            const Divider(),
            const QueueSection(),
            const Divider(),
            const ProfileListSection(),
            const Divider(),
            const OperatorProfileListSection(),
            const Divider(),
            const MaxNodesSection(),
            const Divider(),
            const ProximityAlertsSection(),
            const Divider(),
            const TileProviderSection(),
            const Divider(),
            const OfflineModeSection(),
            const Divider(),
            const OfflineAreasSection(),
            const Divider(),
            const LanguageSection(),
            const Divider(),
            const AboutSection(),
          ],
        ),
      ),
    );
  }
}
