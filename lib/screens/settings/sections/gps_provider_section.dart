import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../services/localization_service.dart';

/// Settings section for choosing GPS location provider on Android.
/// Only visible on Android where both LocationManager and Google Fused are available.
class GpsProviderSection extends StatelessWidget {
  const GpsProviderSection({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return const SizedBox.shrink();

    return Consumer<AppState>(
      builder: (context, appState, child) {
        final locService = LocalizationService.instance;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              locService.t('gpsProvider.title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),

            SwitchListTile(
              title: Text(locService.t('gpsProvider.useGoogleLocation')),
              subtitle: Text(locService.t('gpsProvider.useGoogleLocationSubtitle')),
              value: !appState.forceLocationManager,
              onChanged: (useGoogle) {
                appState.setForceLocationManager(!useGoogle);
              },
              contentPadding: EdgeInsets.zero,
            ),
          ],
        );
      },
    );
  }
}
