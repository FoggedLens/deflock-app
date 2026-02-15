import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

/// Small icon in the AppBar showing USB scanner connection state.
/// Tapping navigates to the scanner screen.
class ScannerStatusIndicator extends StatelessWidget {
  const ScannerStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final status = appState.scannerConnectionStatus;
    final transportLabel = appState.scannerTransportType == ScannerTransportType.ble ? 'BLE' : 'USB';

    final IconData icon;
    final Color color;
    final String tooltip;

    switch (status) {
      case ScannerConnectionStatus.connected:
        icon = Icons.sensors;
        color = Colors.green;
        tooltip = 'Scanner connected ($transportLabel)';
      case ScannerConnectionStatus.connecting:
        icon = Icons.sensors;
        color = Colors.orange;
        tooltip = 'Scanner connecting...';
      case ScannerConnectionStatus.error:
        icon = Icons.sensors_off;
        color = Colors.red;
        tooltip = 'Scanner error';
      case ScannerConnectionStatus.disconnected:
        icon = Icons.sensors_off;
        color = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4);
        tooltip = 'Scanner disconnected';
    }

    return IconButton(
      tooltip: tooltip,
      icon: Stack(
        children: [
          Icon(icon, color: color),
          if (status == ScannerConnectionStatus.connected &&
              appState.scannerDetectionCount > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
      onPressed: () => Navigator.pushNamed(context, '/scanner'),
    );
  }
}
