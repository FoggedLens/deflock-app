import 'package:flutter/material.dart';
import '../services/localization_service.dart';
import '../app_state.dart';
import 'package:provider/provider.dart';

class NavigationSettingsScreen extends StatelessWidget {
  const NavigationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final locService = LocalizationService.instance;
    
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) => Scaffold(
        appBar: AppBar(
          title: Text(locService.t('navigation.navigationSettings')),
        ),
        body: Padding(
          padding: EdgeInsets.fromLTRB(
            16, 
            16, 
            16, 
            16 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Coming soon message
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            'Navigation Features',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Navigation and routing settings will be available here. Coming soon:\n\n'
                        '• Surveillance avoidance distance\n'
                        '• Route planning preferences\n'
                        '• Search history management\n'
                        '• Distance units (metric/imperial)',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Placeholder settings (disabled for now)
              _buildDisabledSetting(
                context,
                icon: Icons.warning_outlined,
                title: locService.t('navigation.avoidanceDistance'),
                subtitle: locService.t('navigation.avoidanceDistanceSubtitle'),
                value: '100 ${locService.t('navigation.meters')}',
              ),
              
              const Divider(),
              
              _buildDisabledSetting(
                context,
                icon: Icons.history,
                title: locService.t('navigation.searchHistory'),
                subtitle: locService.t('navigation.searchHistorySubtitle'),
                value: '10 searches',
              ),
              
              const Divider(),
              
              _buildDisabledSetting(
                context,
                icon: Icons.straighten,
                title: locService.t('navigation.units'),
                subtitle: locService.t('navigation.unitsSubtitle'),
                value: locService.t('navigation.metric'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDisabledSetting(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
  }) {
    return Opacity(
      opacity: 0.5,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 16),
          ],
        ),
        enabled: false,
      ),
    );
  }
}