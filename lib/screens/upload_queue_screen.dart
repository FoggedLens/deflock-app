import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../services/localization_service.dart';
import '../state/settings_state.dart';

class UploadQueueScreen extends StatelessWidget {
  const UploadQueueScreen({super.key});

  String _getUploadModeDisplayName(UploadMode mode) {
    final locService = LocalizationService.instance;
    switch (mode) {
      case UploadMode.production:
        return locService.t('uploadMode.production');
      case UploadMode.sandbox:
        return locService.t('uploadMode.sandbox');
      case UploadMode.simulate:
        return locService.t('uploadMode.simulate');
    }
  }

  Color _getUploadModeColor(UploadMode mode) {
    switch (mode) {
      case UploadMode.production:
        return Colors.green; // Green for production (real)
      case UploadMode.sandbox:
        return Colors.orange; // Orange for sandbox (testing)
      case UploadMode.simulate:
        return Colors.grey; // Grey for simulate (fake)
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        final appState = context.watch<AppState>();
        
        return Scaffold(
          appBar: AppBar(
            title: Text(locService.t('queue.title')),
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              16, 
              16, 
              16, 
              16 + MediaQuery.of(context).padding.bottom,
            ),
            children: [
              // Clear Upload Queue button - always visible
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: appState.pendingCount > 0 ? () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(locService.t('queue.clearQueueTitle')),
                        content: Text(locService.t('queue.clearQueueConfirm', params: [appState.pendingCount.toString()])),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(locService.cancel),
                          ),
                          TextButton(
                            onPressed: () {
                              appState.clearQueue();
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(locService.t('queue.queueCleared'))),
                              );
                            },
                            child: Text(locService.t('actions.clear')),
                          ),
                        ],
                      ),
                    );
                  } : null,
                  icon: const Icon(Icons.clear_all),
                  label: Text(locService.t('queue.clearUploadQueue')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: appState.pendingCount > 0 ? null : Theme.of(context).disabledColor.withOpacity(0.1),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              
              // Queue list or empty message
              if (appState.pendingUploads.isEmpty) ...[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 64,
                          color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.4),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          locService.t('queue.nothingInQueue'),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Text(
                  locService.t('queue.pendingItemsCount', params: [appState.pendingCount.toString()]),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                
                // Queue items
                ...appState.pendingUploads.asMap().entries.map((entry) {
                  final index = entry.key;
                  final upload = entry.value;
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        upload.error ? Icons.error : Icons.camera_alt,
                        color: upload.error 
                            ? Colors.red 
                            : _getUploadModeColor(upload.uploadMode),
                      ),
                      title: Text(
                        locService.t('queue.cameraWithIndex', params: [(index + 1).toString()]) +
                        (upload.error ? locService.t('queue.error') : "") +
                        (upload.completing ? locService.t('queue.completing') : "")
                      ),
                      subtitle: Text(
                        locService.t('queue.destination', params: [_getUploadModeDisplayName(upload.uploadMode)]) + '\n' +
                        locService.t('queue.latitude', params: [upload.coord.latitude.toStringAsFixed(6)]) + '\n' +
                        locService.t('queue.longitude', params: [upload.coord.longitude.toStringAsFixed(6)]) + '\n' +
                        locService.t('queue.direction', params: [
                          upload.direction is String 
                              ? upload.direction.toString()
                              : upload.direction.round().toString()
                        ]) + '\n' +
                        locService.t('queue.attempts', params: [upload.attempts.toString()]) +
                        (upload.error ? "\n${locService.t('queue.uploadFailedRetry')}" : "")
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (upload.error && !upload.completing)
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              color: Colors.orange,
                              tooltip: locService.t('queue.retryUpload'),
                              onPressed: () {
                                appState.retryUpload(upload);
                              },
                            ),
                          if (upload.completing)
                            const Icon(Icons.check_circle, color: Colors.green)
                          else
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                appState.removeFromQueue(upload);
                              },
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }
}