import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/camera_profile.dart';

class AddCameraSheet extends StatelessWidget {
  const AddCameraSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final session = appState.session;

    // If the session was cleared before this frame, bail safely.
    if (session == null) {
      return const SizedBox.shrink();
    }

    final profiles = appState.profiles;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            title: const Text('Profile'),
            trailing: DropdownButton<CameraProfile>(
              value: session.profile,
              items: profiles
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                  .toList(),
              onChanged: (p) =>
                  appState.updateSession(profile: p ?? session.profile),
            ),
          ),
          ListTile(
            title: Text('Direction  ${session.directionDegrees.round()}°'),
            subtitle: Slider(
              min: 0,
              max: 359,
              divisions: 359,
              value: session.directionDegrees,
              label: session.directionDegrees.round().toString(),
              onChanged: (v) => appState.updateSession(directionDeg: v),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Submit'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

