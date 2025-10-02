import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../services/localization_service.dart';

/// Settings section for network status indicator configuration
/// Follows brutalist principles: simple, explicit UI that matches existing patterns
class NetworkStatusSection extends StatelessWidget {
  const NetworkStatusSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final locService = LocalizationService.instance;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              locService.t('settings.networkStatusIndicator'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            
            // Enable/disable toggle
            SwitchListTile(
              title: Text(locService.t('networkStatus.showIndicator')),
              subtitle: Text(locService.t('networkStatus.showIndicatorSubtitle')),
              value: appState.networkStatusIndicatorEnabled,
              onChanged: (enabled) {
                appState.setNetworkStatusIndicatorEnabled(enabled);
              },
              contentPadding: EdgeInsets.zero,
            ),
          ],
        );
      },
    );
  }
}