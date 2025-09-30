import 'package:flutter/material.dart';
import 'settings_screen_sections/profile_list_section.dart';
import 'settings_screen_sections/operator_profile_list_section.dart';
import '../services/localization_service.dart';

class ProfilesSettingsScreen extends StatelessWidget {
  const ProfilesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final locService = LocalizationService.instance;
    
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) => Scaffold(
        appBar: AppBar(
          title: Text(locService.t('settings.profiles')),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            ProfileListSection(),
            Divider(),
            OperatorProfileListSection(),
          ],
        ),
      ),
    );
  }
}