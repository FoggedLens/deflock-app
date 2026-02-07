import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app_state.dart';
import '../../../services/localization_service.dart';
import '../../../services/distance_service.dart';
import '../../../state/settings_state.dart';

class SuspectedLocationsSection extends StatefulWidget {
  const SuspectedLocationsSection({super.key});

  @override
  State<SuspectedLocationsSection> createState() => _SuspectedLocationsSectionState();
}

class _SuspectedLocationsSectionState extends State<SuspectedLocationsSection> {
  DateTime? _lastFetch;
  bool _wasLoading = false;

  @override
  void initState() {
    super.initState();
    _loadLastFetch();
  }

  void _loadLastFetch() async {
    final appState = context.read<AppState>();
    final lastFetch = await appState.suspectedLocationsLastFetch;
    if (mounted) {
      setState(() {
        _lastFetch = lastFetch;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        final appState = context.watch<AppState>();
        final isEnabled = appState.suspectedLocationsEnabled;
        final isLoading = appState.suspectedLocationsLoading;
        final downloadProgress = appState.suspectedLocationsDownloadProgress;
        
        // Check if loading just finished and reload last fetch time
        if (_wasLoading && !isLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _loadLastFetch();
          });
        }
        _wasLoading = isLoading;
        
        String getLastFetchText() {
          // Show status during loading
          if (isLoading) {
            if (downloadProgress != null) {
              return 'Downloading data... (this may take a few minutes)';
            } else {
              return 'Processing data...';
            }
          }
          
          if (_lastFetch == null) {
            return locService.t('suspectedLocations.neverFetched');
          } else {
            final now = DateTime.now();
            final diff = now.difference(_lastFetch!);
            if (diff.inDays > 0) {
              return locService.t('suspectedLocations.daysAgo', params: [diff.inDays.toString()]);
            } else if (diff.inHours > 0) {
              return locService.t('suspectedLocations.hoursAgo', params: [diff.inHours.toString()]);
            } else if (diff.inMinutes > 0) {
              return locService.t('suspectedLocations.minutesAgo', params: [diff.inMinutes.toString()]);
            } else {
              return locService.t('suspectedLocations.justNow');
            }
          }
        }
        
        Future<void> handleRefresh() async {
          if (!context.mounted) return;
          
          // Use the inline loading indicator by calling refreshSuspectedLocations
          // The loading state will be managed by suspected location state
          final success = await appState.refreshSuspectedLocations();
          
          // Refresh the last fetch time after successful refresh
          if (success) {
            _loadLastFetch();
          }
          
          // Show result snackbar
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(success 
                    ? locService.t('suspectedLocations.updateSuccess')
                    : locService.t('suspectedLocations.updateFailed')),
              ),
            );
          }
        }
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              locService.t('suspectedLocations.title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            
            // Enable/disable switch
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: Text(locService.t('suspectedLocations.showSuspectedLocations')),
              subtitle: Text(locService.t('suspectedLocations.showSuspectedLocationsSubtitle')),
              trailing: Switch(
                value: isEnabled,
                onChanged: (enabled) {
                  appState.setSuspectedLocationsEnabled(enabled);
                },
              ),
            ),
            
            if (isEnabled) ...[
              const SizedBox(height: 8),
              
              // Last update time
              ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(locService.t('suspectedLocations.lastUpdated')),
                subtitle: Text(getLastFetchText()),
                trailing: isLoading
                    ? SizedBox(
                        width: 80,
                        height: 24,
                        child: downloadProgress != null
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  LinearProgressIndicator(
                                    value: downloadProgress,
                                    backgroundColor: Colors.grey[300],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${(downloadProgress * 100).toInt()}%',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              )
                            : const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: handleRefresh,
                        tooltip: locService.t('suspectedLocations.refreshNow'),
                      ),
              ),
              
              // Data info with credit
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(locService.t('suspectedLocations.dataSource')),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(locService.t('suspectedLocations.dataSourceDescription')),
                    const SizedBox(height: 4),
                    Text(
                      locService.t('suspectedLocations.dataSourceCredit'),
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Minimum distance setting
              ListTile(
                leading: const Icon(Icons.social_distance),
                title: Text(locService.t('suspectedLocations.minimumDistance')),
                subtitle: Text(locService.t('suspectedLocations.minimumDistanceSubtitle', params: [
                  DistanceService.formatDistance(appState.suspectedLocationMinDistance.toDouble(), appState.distanceUnit)
                ])),
                trailing: SizedBox(
                  width: 80,
                  child: TextFormField(
                    initialValue: DistanceService.convertFromMeters(
                      appState.suspectedLocationMinDistance.toDouble(),
                      appState.distanceUnit
                    ).round().toString(),
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      border: const OutlineInputBorder(),
                      suffixText: DistanceService.getSmallDistanceUnit(appState.distanceUnit),
                    ),
                    onFieldSubmitted: (value) {
                      final displayValue = double.tryParse(value) ?? (appState.distanceUnit == DistanceUnit.metric ? 100.0 : 328.0);
                      final metersValue = DistanceService.convertToMeters(displayValue, appState.distanceUnit, isSmallDistance: true);
                      appState.setSuspectedLocationMinDistance(metersValue.round().clamp(0, 1000));
                    },
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}