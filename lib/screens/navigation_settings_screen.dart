import 'package:flutter/material.dart';
import '../services/localization_service.dart';
import '../app_state.dart';
import 'package:provider/provider.dart';

class NavigationSettingsScreen extends StatelessWidget {
  const NavigationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
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
              ListTile(
                leading: const Icon(Icons.social_distance),
                title: Text(locService.t('navigation.avoidanceDistance')),
                subtitle: Text(locService.t('navigation.avoidanceDistanceSubtitle')),
                trailing: SizedBox(
                  width: 80,
                  child: TextFormField(
                    initialValue: appState.navigationAvoidanceDistance.toString(),
                    keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      border: OutlineInputBorder(),
                      suffixText: 'm',
                    ),
                    onFieldSubmitted: (value) {
                      final distance = int.tryParse(value) ?? 250;
                      appState.setNavigationAvoidanceDistance(distance.clamp(0, 2000));
                    }
                  )
                )
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
