import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../services/localization_service.dart';
import '../../dev_config.dart';

/// Settings section for proximity alerts configuration
/// Follows brutalist principles: simple, explicit UI that matches existing patterns
class ProximityAlertsSection extends StatefulWidget {
  const ProximityAlertsSection({super.key});

  @override
  State<ProximityAlertsSection> createState() => _ProximityAlertsSectionState();
}

class _ProximityAlertsSectionState extends State<ProximityAlertsSection> {
  late final TextEditingController _distanceController;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _distanceController = TextEditingController(
      text: appState.proximityAlertDistance.toString(),
    );
  }

  @override
  void dispose() {
    _distanceController.dispose();
    super.dispose();
  }

  void _updateDistance(AppState appState) {
    final text = _distanceController.text.trim();
    final distance = int.tryParse(text);
    if (distance != null) {
      appState.setProximityAlertDistance(distance);
    } else {
      // Reset to current value if invalid
      _distanceController.text = appState.proximityAlertDistance.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Proximity Alerts',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            // Enable/disable toggle
            SwitchListTile(
              title: const Text('Enable proximity alerts'),
              subtitle: const Text(
                'Get notified when approaching surveillance devices\n'
                'Uses extra battery for continuous location monitoring',
                style: TextStyle(fontSize: 12),
              ),
              value: appState.proximityAlertsEnabled,
              onChanged: (enabled) {
                appState.setProximityAlertsEnabled(enabled);
              },
              contentPadding: EdgeInsets.zero,
            ),
            
            // Distance setting (only show when enabled)
            if (appState.proximityAlertsEnabled) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Alert distance: '),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _distanceController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8, 
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _updateDistance(appState),
                      onEditingComplete: () => _updateDistance(appState),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('meters'),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Range: $kProximityAlertMinDistance-$kProximityAlertMaxDistance meters (default: $kProximityAlertDefaultDistance)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}