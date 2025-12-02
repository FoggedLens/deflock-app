import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';

import '../app_state.dart';
import '../dev_config.dart';
import '../services/localization_service.dart';

class NavigationSheet extends StatelessWidget {
  final VoidCallback? onStartRoute;
  final VoidCallback? onResumeRoute;
  
  const NavigationSheet({
    super.key,
    this.onStartRoute,
    this.onResumeRoute,
  });

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
                  label: LocalizationService.instance.t('navigation.location'),
                  coordinates: provisionalLocation,
                  address: provisionalAddress,
                ),
                const SizedBox(height: 16),
                // Only show routing buttons if navigation features are enabled
                if (enableNavigationFeatures(offlineMode: appState.offlineMode)) ...[
                  Row(
                    children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.directions),
                            label: Text(LocalizationService.instance.t('navigation.routeTo')),
                            onPressed: () {
                              appState.startRoutePlanning(thisLocationIsStart: false);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.my_location),
                            label: Text(LocalizationService.instance.t('navigation.routeFrom')),
                            onPressed: () {
                              appState.startRoutePlanning(thisLocationIsStart: true);
                            },
                          ),
                        ),
                    ],
                  ),
                ],
              ],

              // SETTING SECOND POINT: Show both points and select button
              if (appState.isSettingSecondPoint && provisionalLocation != null) ...[
                // Show existing route points
                if (appState.routeStart != null) ...[
                  _buildLocationInfo(
                    label: LocalizationService.instance.t('navigation.startPoint'),
                    coordinates: appState.routeStart!,
                    address: appState.routeStartAddress,
                  ),
                  const SizedBox(height: 12),
                ],
                if (appState.routeEnd != null) ...[
                  _buildLocationInfo(
                    label: LocalizationService.instance.t('navigation.endPoint'),
                    coordinates: appState.routeEnd!,
                    address: appState.routeEndAddress,
                  ),
                  const SizedBox(height: 12),
                ],
                
                // Show the point we're selecting
                _buildLocationInfo(
                  label: appState.settingRouteStart 
                    ? LocalizationService.instance.t('navigation.startSelect')
                    : LocalizationService.instance.t('navigation.endSelect'),
                  coordinates: provisionalLocation,
                  address: provisionalAddress,
                ),
                const SizedBox(height: 16),
                
                // Show warning message if locations are too close
                if (appState.areRoutePointsTooClose) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange[700], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            LocalizationService.instance.t('navigation.locationsTooClose'),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.orange[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                
                ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: Text(LocalizationService.instance.t('navigation.selectLocation')),
                  onPressed: appState.areRoutePointsTooClose ? null : () {
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
                Text(
                  LocalizationService.instance.t('navigation.calculatingRoute'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => appState.cancelNavigation(),
                  child: Text(LocalizationService.instance.t('actions.cancel')),
                ),
              ],

              // ROUTING ERROR: Show error with retry option
              if (appState.hasRoutingError && !appState.isCalculating) ...[
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Colors.red[400],
                ),
                const SizedBox(height: 16),
                Text(
                  LocalizationService.instance.t('navigation.routeCalculationFailed'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  appState.routingError ?? 'Unknown error',
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: Text(LocalizationService.instance.t('navigation.retry')),
                        onPressed: () {
                          // Retry route calculation
                          appState.retryRouteCalculation();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.close),
                        label: Text(LocalizationService.instance.t('actions.cancel')),
                        onPressed: () => appState.cancelNavigation(),
                      ),
                    ),
                  ],
                ),
              ],

              // ROUTE OVERVIEW: Show route details with start/cancel options
              if (appState.showingOverview) ...[
                if (appState.routeStart != null) ...[
                  _buildLocationInfo(
                    label: LocalizationService.instance.t('navigation.startPoint'),
                    coordinates: appState.routeStart!,
                    address: appState.routeStartAddress,
                  ),
                  const SizedBox(height: 12),
                ],
                if (appState.routeEnd != null) ...[
                  _buildLocationInfo(
                    label: LocalizationService.instance.t('navigation.endPoint'),
                    coordinates: appState.routeEnd!,
                    address: appState.routeEndAddress,
                  ),
                  const SizedBox(height: 12),
                ],
                if (appState.routeDistance != null) ...[
                  Text(
                    LocalizationService.instance.t('navigation.distance', params: [(appState.routeDistance! / 1000).toStringAsFixed(1)]),
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
                          label: Text(LocalizationService.instance.t('navigation.start')),
                          onPressed: onStartRoute ?? () => appState.startRoute(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.close),
                          label: Text(LocalizationService.instance.t('actions.cancel')),
                          onPressed: () => appState.cancelNavigation(),
                        ),
                      ),
                    ] else if (navigationMode == AppNavigationMode.routeActive) ...[
                      // Active route overview - resume or cancel
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: Text(LocalizationService.instance.t('navigation.resume')),
                          onPressed: onResumeRoute ?? () => appState.hideRouteOverview(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.close),
                          label: Text(LocalizationService.instance.t('navigation.endRoute')),
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