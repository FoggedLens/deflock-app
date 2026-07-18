import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../../app_state.dart';
import '../../../../../../../services/localization_service.dart';

/// Settings section for the stale-node visual indicator.
/// Threshold is a discrete set of days, not an arbitrary number,
/// per the original spec.
class StalenessIndicatorSection extends StatelessWidget {
  const StalenessIndicatorSection({super.key});

  static const List<int> _thresholdOptions = [30, 60, 180, 365];

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

            // Threshold picker (only shown when enabled)
            if (appState.stalenessIndicatorEnabled) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(locService.t('staleness.threshold')),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value:
                        _thresholdOptions.contains(
                          appState.stalenessThresholdDays,
                        )
                        ? appState.stalenessThresholdDays
                        : _thresholdOptions.last,
                    items: _thresholdOptions
                        .map(
                          (days) => DropdownMenuItem<int>(
                            value: days,
                            child: Text(
                              locService.t(
                                'staleness.daysCount',
                                params: [days.toString()],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (days) {
                      if (days != null) {
                        appState.setStalenessThresholdDays(days);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                locService.t('staleness.explanation'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
