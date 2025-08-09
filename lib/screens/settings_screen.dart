import 'package:flutter/material.dart';
import 'settings_screen_sections/auth_section.dart';
import 'settings_screen_sections/upload_mode_section.dart';
import 'settings_screen_sections/profile_list_section.dart';
import 'settings_screen_sections/queue_section.dart';
import 'settings_screen_sections/offline_areas_section.dart';
import 'settings_screen_sections/offline_mode_section.dart';
import 'settings_screen_sections/about_section.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          AuthSection(),
          Divider(),
          UploadModeSection(),
          Divider(),
          QueueSection(),
          Divider(),
          ProfileListSection(),
          Divider(),
          OfflineModeSection(),
          Divider(),
          OfflineAreasSection(),
          Divider(),
          AboutSection(),
        ],
      ),
    );
  }
}
