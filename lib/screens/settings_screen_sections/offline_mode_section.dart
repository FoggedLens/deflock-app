import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';

class OfflineModeSection extends StatelessWidget {
  const OfflineModeSection({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return ListTile(
      leading: const Icon(Icons.wifi_off),
      title: const Text('Offline Mode'),
      subtitle: const Text('Disable all network requests except for local/offline areas.'),
      trailing: Switch(
        value: appState.offlineMode,
        onChanged: (value) async => await appState.setOfflineMode(value),
      ),
    );
  }
}
