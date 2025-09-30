import 'package:flutter/material.dart';
import 'settings/sections/auth_section.dart';
import 'settings/sections/upload_mode_section.dart';
import 'settings/sections/queue_section.dart';
import '../services/localization_service.dart';
import '../dev_config.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final locService = LocalizationService.instance;
    
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) => Scaffold(
        appBar: AppBar(title: Text(locService.t('settings.title'))),
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
            
            // Navigation to sub-pages
            _buildNavigationTile(
              context,
              icon: Icons.account_tree,
              title: locService.t('settings.profiles'),
              subtitle: locService.t('settings.profilesSubtitle'),
              onTap: () => Navigator.pushNamed(context, '/settings/profiles'),
            ),
            const Divider(),
            
            _buildNavigationTile(
              context,
              icon: Icons.cloud_off,
              title: locService.t('settings.offlineSettings'),
              subtitle: locService.t('settings.offlineSettingsSubtitle'),
              onTap: () => Navigator.pushNamed(context, '/settings/offline'),
            ),
            const Divider(),
            
            _buildNavigationTile(
              context,
              icon: Icons.tune,
              title: locService.t('settings.advancedSettings'),
              subtitle: locService.t('settings.advancedSettingsSubtitle'),
              onTap: () => Navigator.pushNamed(context, '/settings/advanced'),
            ),
            const Divider(),
            
            _buildNavigationTile(
              context,
              icon: Icons.language,
              title: locService.t('settings.language'),
              subtitle: locService.t('settings.languageSubtitle'),
              onTap: () => Navigator.pushNamed(context, '/settings/language'),
            ),
            const Divider(),
            
            _buildNavigationTile(
              context,
              icon: Icons.info_outline,
              title: locService.t('settings.aboutInfo'),
              subtitle: locService.t('settings.aboutSubtitle'),
              onTap: () => Navigator.pushNamed(context, '/settings/about'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }
}
