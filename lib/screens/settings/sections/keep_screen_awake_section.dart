import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app_state.dart';
import '../../../services/localization_service.dart';

class KeepScreenAwakeSection extends StatelessWidget {
  const KeepScreenAwakeSection({super.key});

  @override
  Widget build(BuildContext context) {
    // Standard Pattern: Use AnimatedBuilder to respond to language/localization changes
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        final appState = context.watch<AppState>();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bold Section Header (matches Max Nodes, Proximity, etc.)
            Text(
              locService.t('settings.keepScreenAwake'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),

            // The Functional Toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero, // Aligns switch text with the bold header
              title: Text(locService.t('keepScreenAwake.title')),
              subtitle: Text(
                locService.t('keepScreenAwake.subtitle'),
                style: const TextStyle(fontSize: 12),
              ),
              value: appState.keepScreenAwake,
              onChanged: (bool value) {
                appState.setKeepScreenAwake(value);
              },
            ),
          ],
        );
      },
    );
  }
}