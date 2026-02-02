import 'package:flutter/material.dart';
import 'settings/sections/max_nodes_section.dart';
import 'settings/sections/proximity_alerts_section.dart';
import 'settings/sections/suspected_locations_section.dart';
import 'settings/sections/tile_provider_section.dart';
import '../services/localization_service.dart';

class AdvancedSettingsScreen extends StatelessWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final locService = LocalizationService.instance;
    
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) => Scaffold(
        appBar: AppBar(
          title: Text(locService.t('settings.advancedSettings')),
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            16, 
            16, 
            16, 
            16 + MediaQuery.of(context).padding.bottom,
          ),
          children: const [
            MaxNodesSection(),
            Divider(),
            ProximityAlertsSection(),
            Divider(),
            SuspectedLocationsSection(),
            Divider(),
            // NetworkStatusSection(), // Commented out - network status indicator now defaults to enabled
            // Divider(),
            TileProviderSection(),
          ],
        ),
      ),
    );
  }
}