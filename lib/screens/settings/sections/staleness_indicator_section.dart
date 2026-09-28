import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../../app_state.dart';
import '../../../../../../../services/localization_service.dart';

/// Settings section for the stale-node visual indicator.
/// Threshold is a discrete set of days, not an arbitrary number,
/// per the original spec.
class StalenessIndicatorSection extends StatelessWidget {
  const StalenessIndicatorSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final locService = LocalizationService.instance;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              locService.t('settings.dataFreshness'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),

            // Enable/disable toggle
            SwitchListTile(
              title: Text(locService.t('staleness.showIndicator')),
              subtitle: Text(
                locService.t('staleness.showIndicatorExplanation'),
                style: const TextStyle(fontSize: 12),
              ),
              value: appState.stalenessIndicatorEnabled,
              onChanged: (enabled) {
                appState.setStalenessIndicatorEnabled(enabled);
              },
              contentPadding: EdgeInsets.zero,
            ),
          ],
        );
      },
    );
  }
}
