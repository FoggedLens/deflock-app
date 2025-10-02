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

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.grey[400],
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final navigationMode = appState.navigationMode;
        final provisionalLocation = appState.provisionalPinLocation;
        final provisionalAddress = appState.provisionalPinAddress;

        if (provisionalLocation == null && !appState.showingOverview) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDragHandle(),
              
              // SEARCH MODE: Initial location with route options
              if (navigationMode == AppNavigationMode.search && !appState.isSettingSecondPoint && !appState.isCalculating && !appState.showingOverview && provisionalLocation != null) ...[
                _buildLocationInfo(
                  label: 'Location',
                  coordinates: provisionalLocation,
                  address: provisionalAddress,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.directions),
                        label: const Text('Route To'),
                        onPressed: () {
                          appState.startRoutePlanning(thisLocationIsStart: false);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.my_location),
                        label: const Text('Route From'),
                        onPressed: () {
                          appState.startRoutePlanning(thisLocationIsStart: true);
                        },
                      ),
                    ),
                  ],
                ),
              ],

              // SETTING SECOND POINT: Show both points and select button
              if (appState.isSettingSecondPoint && provisionalLocation != null) ...[
                // Show existing route points
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
                
                // Show the point we're selecting
                _buildLocationInfo(
                  label: appState.settingRouteStart ? 'Start (select)' : 'End (select)',
                  coordinates: provisionalLocation,
                  address: provisionalAddress,
                ),
                const SizedBox(height: 16),
                
                ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Select Location'),
                  onPressed: () {
                    debugPrint('[NavigationSheet] Select Location button pressed');
                    appState.selectSecondRoutePoint();
                  },
                ),
              ],

              // CALCULATING: Show loading
              if (appState.isCalculating) ...[
                const Center(
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Calculating route...', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => appState.cancelNavigation(),
                  child: const Text('Cancel'),
                ),
              ],

              // ROUTE OVERVIEW: Show route details with start/cancel options
              if (appState.showingOverview) ...[
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
                if (appState.routeDistance != null) ...[
                  Text(
                    'Distance: ${(appState.routeDistance! / 1000).toStringAsFixed(1)} km',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                ],
                
                Row(
                  children: [
                    if (navigationMode == AppNavigationMode.search) ...[
                      // Route preview mode - start or cancel
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start'),
                          onPressed: () => appState.startRoute(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.close),
                          label: const Text('Cancel'),
                          onPressed: () => appState.cancelNavigation(),
                        ),
                      ),
                    ] else if (navigationMode == AppNavigationMode.routeActive) ...[
                      // Active route overview - resume or cancel
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Resume'),
                          onPressed: () => appState.hideRouteOverview(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.close),
                          label: const Text('End Route'),
                          onPressed: () => appState.cancelRoute(),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}