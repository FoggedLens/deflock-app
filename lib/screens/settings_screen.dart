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
import 'settings_screen_sections/tile_provider_section.dart';
import 'settings_screen_sections/language_section.dart';
import '../services/localization_service.dart';

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
          children: const [
            UploadModeSection(),
            Divider(),
            AuthSection(),
            Divider(),
            QueueSection(),
            Divider(),
            ProfileListSection(),
            Divider(),
            OperatorProfileListSection(),
            Divider(),
            MaxNodesSection(),
            Divider(),
            TileProviderSection(),
            Divider(),
            OfflineModeSection(),
            Divider(),
            OfflineAreasSection(),
            Divider(),
            LanguageSection(),
            Divider(),
            AboutSection(),
          ],
        ),
      ),
    );
  }
}
