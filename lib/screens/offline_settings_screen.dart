import 'package:flutter/material.dart';
import 'settings_screen_sections/offline_mode_section.dart';
import 'settings_screen_sections/offline_areas_section.dart';
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
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            OfflineModeSection(),
            Divider(),
            OfflineAreasSection(),
          ],
        ),
      ),
    );
  }
}