import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../services/localization_service.dart';
import '../../../services/proximity_alert_service.dart';
import '../../../dev_config.dart';

/// Settings section for proximity alerts configuration
/// Follows brutalist principles: simple, explicit UI that matches existing patterns
class ProximityAlertsSection extends StatefulWidget {
  const ProximityAlertsSection({super.key});

  @override
  State<ProximityAlertsSection> createState() => _ProximityAlertsSectionState();
}

class _ProximityAlertsSectionState extends State<ProximityAlertsSection> {
  late final TextEditingController _distanceController;
  bool _notificationsEnabled = false;
  bool _checkingPermissions = false;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _distanceController = TextEditingController(
      text: appState.proximityAlertDistance.toString(),
    );
    _checkNotificationPermissions();
  }
  
  Future<void> _checkNotificationPermissions() async {
    setState(() {
      _checkingPermissions = true;
    });
    
    final enabled = await ProximityAlertService().areNotificationsEnabled();
    
    if (mounted) {
      setState(() {
        _notificationsEnabled = enabled;
        _checkingPermissions = false;
      });
    }
  }
  
  Future<void> _requestNotificationPermissions() async {
    setState(() {
      _checkingPermissions = true;
    });
    
    final enabled = await ProximityAlertService().requestNotificationPermissions();
    
    if (mounted) {
      setState(() {
        _notificationsEnabled = enabled;
        _checkingPermissions = false;
      });
    }
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
        final locService = LocalizationService.instance;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              locService.t('settings.proximityAlerts'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            
            // Enable/disable toggle
            SwitchListTile(
              title: Text(locService.t('proximityAlerts.getNotified')),
              subtitle: Text(
                '${locService.t('proximityAlerts.batteryUsage')}\n'
                '${_notificationsEnabled ? locService.t('proximityAlerts.notificationsEnabled') : locService.t('proximityAlerts.notificationsDisabled')}',
                style: TextStyle(fontSize: 12),
              ),
              value: appState.proximityAlertsEnabled,
              onChanged: (enabled) {
                appState.setProximityAlertsEnabled(enabled);
                if (enabled && !_notificationsEnabled) {
                  // Automatically try to request permissions when enabling
                  _requestNotificationPermissions();
                }
              },
              contentPadding: EdgeInsets.zero,
            ),
            
            // Notification permissions section (only show when proximity alerts are enabled)
            if (appState.proximityAlertsEnabled && !_notificationsEnabled && !_checkingPermissions) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.notifications_off, color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          locService.t('proximityAlerts.permissionRequired'),
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      locService.t('proximityAlerts.permissionExplanation'),
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _requestNotificationPermissions,
                      icon: const Icon(Icons.settings, size: 16),
                      label: Text(locService.t('proximityAlerts.enableNotifications')),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            // Loading indicator
            if (_checkingPermissions) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(locService.t('proximityAlerts.checkingPermissions'), style: TextStyle(fontSize: 12)),
                ],
              ),
            ],
            
            // Distance setting (only show when enabled)
            if (appState.proximityAlertsEnabled) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(locService.t('proximityAlerts.alertDistance')),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _distanceController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
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
                  Text(locService.t('proximityAlerts.meters')),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                locService.t('proximityAlerts.rangeInfo', params: [
                  kProximityAlertMinDistance.toString(),
                  kProximityAlertMaxDistance.toString(),
                  kProximityAlertDefaultDistance.toString(),
                ]),
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