import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app_state.dart';

class KeepScreenAwakeSection extends StatelessWidget {
  const KeepScreenAwakeSection({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return SwitchListTile(
      title: const Text('Keep screen awake while using app'),
      subtitle: const Text('Prevents the screen from turning off automatically while using the app'),
      value: appState.keepScreenAwake,
      onChanged: (bool value) {
        appState.setKeepScreenAwake(value);
      },
    );
  }
}