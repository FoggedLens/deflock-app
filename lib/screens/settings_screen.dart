import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../services/localization_service.dart';
import '../services/version_service.dart';
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
          padding: EdgeInsets.fromLTRB(
            16, 
            16, 
            16, 
            16 + MediaQuery.of(context).padding.bottom,
          ),
          children: [
            // OpenStreetMap Account
            _buildOSMAccountTile(context, locService),
            const Divider(),
            
            // Upload Queue
            _buildNavigationTile(
              context,
              icon: Icons.queue,
              title: locService.t('queue.title'),
              subtitle: locService.t('queue.subtitle'),
              onTap: () => Navigator.pushNamed(context, '/settings/queue'),
            ),
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
            
            // Only show navigation settings in development builds
            if (kEnableNavigationFeatures) ...[
              _buildNavigationTile(
                context,
                icon: Icons.navigation,
                title: locService.t('navigation.navigationSettings'),
                subtitle: locService.t('navigation.navigationSettingsSubtitle'),
                onTap: () => Navigator.pushNamed(context, '/settings/navigation'),
              ),
              const Divider(),
            ],
            
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
            const Divider(),
            
            // Version display
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Version: ${VersionService().version}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOSMAccountTile(BuildContext context, LocalizationService locService) {
    final appState = context.watch<AppState>();
    
    return ListTile(
      leading: Stack(
        children: [
          const Icon(Icons.account_circle),
          if (appState.hasUnreadMessages && appState.uploadMode != UploadMode.simulate)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      title: Text(locService.t('auth.osmAccountTitle')),
      subtitle: Text(locService.t('auth.osmAccountSubtitle')),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () => Navigator.pushNamed(context, '/settings/osm-account'),
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
