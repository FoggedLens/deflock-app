import 'package:flutter/material.dart';
import 'settings/sections/language_section.dart';
import '../services/localization_service.dart';

class LanguageSettingsScreen extends StatelessWidget {
  const LanguageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final locService = LocalizationService.instance;
    
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) => Scaffold(
        appBar: AppBar(
          title: Text(locService.t('settings.language')),
        ),
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: LanguageSection(),
        ),
      ),
    );
  }
}