import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';

import '../app_state.dart';

class NavigationSheet extends StatelessWidget {
  const NavigationSheet({super.key});

  String _formatCoordinates(LatLng coordinates) {
    return '${coordinates.latitude.toStringAsFixed(6)}, ${coordinates.longitude.toStringAsFixed(6)}';
  }

  Widget _buildLocationInfo({
    required String label,
    required LatLng coordinates,
    String? address,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        if (address != null) ...[
          Text(
            address,
            style: const TextStyle(fontSize: 16),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
        ],
        Text(
          _formatCoordinates(coordinates),
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final navigationMode = appState.navigationMode;
        final provisionalLocation = appState.provisionalPinLocation;
        final provisionalAddress = appState.provisionalPinAddress;

        if (provisionalLocation == null) {
          return const SizedBox.shrink();
        }

        switch (navigationMode) {
          case AppNavigationMode.search:
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  
                  // Location info
                  _buildLocationInfo(
                    label: 'Location',
                    coordinates: provisionalLocation,
                    address: provisionalAddress,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.directions),
                          label: const Text('Route To'),
                          onPressed: () {
                            appState.startRouteSetup(settingStart: false);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.my_location),
                          label: const Text('Route From'),
                          onPressed: () {
                            appState.startRouteSetup(settingStart: true);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );

          case AppNavigationMode.routeSetup:
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  
                  // Route points info
                  if (appState.routeStart != null) ...[
                    _buildLocationInfo(
                      label: 'Start',
                      coordinates: appState.routeStart!,
                      address: appState.routeStartAddress,
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  if (appState.routeEnd != null) ...[
                    _buildLocationInfo(
                      label: 'End',
                      coordinates: appState.routeEnd!,
                      address: appState.routeEndAddress,
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  _buildLocationInfo(
                    label: appState.settingRouteStart ? 'Start (select)' : 'End (select)',
                    coordinates: provisionalLocation,
                    address: provisionalAddress,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Select location button
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Select Location'),
                    onPressed: () {
                      debugPrint('[NavigationSheet] Select Location button pressed');
                      appState.selectRouteLocation();
                    },
                  ),
                ],
              ),
            );

          case AppNavigationMode.routeCalculating:
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('Calculating route...'),
                  const SizedBox(height: 16),
                  
                  ElevatedButton(
                    onPressed: () {
                      appState.cancelRoute();
                    },
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            );

          case AppNavigationMode.routePreview:
          case AppNavigationMode.routeOverview:
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  
                  // Route info
                  if (appState.routeStart != null) ...[
                    _buildLocationInfo(
                      label: 'Start',
                      coordinates: appState.routeStart!,
                      address: appState.routeStartAddress,
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  if (appState.routeEnd != null) ...[
                    _buildLocationInfo(
                      label: 'End',
                      coordinates: appState.routeEnd!,
                      address: appState.routeEndAddress,
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  // Distance info
                  if (appState.routeDistance != null) ...[
                    Text(
                      'Distance: ${(appState.routeDistance! / 1000).toStringAsFixed(1)} km',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // Action buttons
                  Row(
                    children: [
                      if (navigationMode == AppNavigationMode.routePreview) ...[
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Start'),
                            onPressed: () {
                              appState.startRoute();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                      ] else if (navigationMode == AppNavigationMode.routeOverview) ...[
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Resume'),
                            onPressed: () {
                              appState.returnToActiveRoute();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.close),
                          label: const Text('Cancel'),
                          onPressed: () {
                            appState.cancelRoute();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );

          default:
            return const SizedBox.shrink();
        }
      },
    );
  }
}