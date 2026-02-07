import 'package:flutter/material.dart';
import '../services/localization_service.dart';
import '../services/distance_service.dart';
import '../app_state.dart';
import '../state/settings_state.dart';
import 'package:provider/provider.dart';

class NavigationSettingsScreen extends StatefulWidget {
  const NavigationSettingsScreen({super.key});

  @override
  State<NavigationSettingsScreen> createState() => _NavigationSettingsScreenState();
}

class _NavigationSettingsScreenState extends State<NavigationSettingsScreen> {
  late TextEditingController _distanceController;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    final displayValue = DistanceService.convertFromMeters(
      appState.navigationAvoidanceDistance.toDouble(), 
      appState.distanceUnit
    );
    _distanceController = TextEditingController(
      text: displayValue.round().toString(),
    );
  }

  @override
  void dispose() {
    _distanceController.dispose();
    super.dispose();
  }

  void _updateDistance(AppState appState, String value) {
    final displayValue = double.tryParse(value) ?? (appState.distanceUnit == DistanceUnit.metric ? 250.0 : 820.0);
    final metersValue = DistanceService.convertToMeters(displayValue, appState.distanceUnit, isSmallDistance: true);
    appState.setNavigationAvoidanceDistance(metersValue.round().clamp(0, 2000));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        // Update the text field when the unit or distance changes
        final displayValue = DistanceService.convertFromMeters(
          appState.navigationAvoidanceDistance.toDouble(), 
          appState.distanceUnit
        );
        if (_distanceController.text != displayValue.round().toString()) {
          _distanceController.text = displayValue.round().toString();
        }
        
        final locService = LocalizationService.instance;
        
        return AnimatedBuilder(
          animation: LocalizationService.instance,
          builder: (context, child) {
            return Scaffold(
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
                        child: TextField(
                          controller: _distanceController,
                          keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                            border: const OutlineInputBorder(),
                            suffixText: DistanceService.getSmallDistanceUnit(appState.distanceUnit),
                          ),
                          onSubmitted: (value) => _updateDistance(appState, value),
                          onEditingComplete: () => _updateDistance(appState, _distanceController.text),
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
                  ],
                ),
              ),
            );
          },
        );
      },
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
