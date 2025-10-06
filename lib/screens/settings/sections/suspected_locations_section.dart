import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app_state.dart';
import '../../../services/localization_service.dart';

class SuspectedLocationsSection extends StatelessWidget {
  const SuspectedLocationsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        final appState = context.watch<AppState>();
        final isEnabled = appState.suspectedLocationsEnabled;
        final isLoading = appState.suspectedLocationsLoading;
        final lastFetch = appState.suspectedLocationsLastFetch;
        
        String getLastFetchText() {
          if (lastFetch == null) {
            return 'Never fetched';
          } else {
            final now = DateTime.now();
            final diff = now.difference(lastFetch);
            if (diff.inDays > 0) {
              return '${diff.inDays} days ago';
            } else if (diff.inHours > 0) {
              return '${diff.inHours} hours ago';
            } else if (diff.inMinutes > 0) {
              return '${diff.inMinutes} minutes ago';
            } else {
              return 'Just now';
            }
          }
        }
        
        Future<void> handleRefresh() async {
          final success = await appState.refreshSuspectedLocations();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(success 
                    ? 'Suspected locations updated successfully' 
                    : 'Failed to update suspected locations'),
              ),
            );
          }
        }
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Suspected Locations',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            
            // Enable/disable switch
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Show Suspected Locations'),
              subtitle: const Text('Show question mark markers for suspected surveillance sites from utility permit data'),
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
                title: const Text('Last Updated'),
                subtitle: Text(getLastFetchText()),
                trailing: isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: handleRefresh,
                        tooltip: 'Refresh now',
                      ),
              ),
              
              // Data info
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Data Source'),
                subtitle: const Text('Utility permit data indicating potential surveillance infrastructure installation sites'),
              ),
            ],
          ],
        );
      },
    );
  }
}