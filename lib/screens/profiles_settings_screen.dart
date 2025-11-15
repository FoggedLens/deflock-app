import 'package:flutter/material.dart';
import 'settings/sections/node_profiles_section.dart';
import 'settings/sections/operator_profiles_section.dart';
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
          padding: EdgeInsets.fromLTRB(
            16, 
            16, 
            16, 
            16 + MediaQuery.of(context).padding.bottom,
          ),
          children: const [
            NodeProfilesSection(),
            Divider(),
            OperatorProfilesSection(),
          ],
        ),
      ),
    );
  }
}