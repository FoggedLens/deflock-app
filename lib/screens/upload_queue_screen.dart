import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/pending_upload.dart';
import '../services/localization_service.dart';
import '../state/settings_state.dart';

class UploadQueueScreen extends StatelessWidget {
  const UploadQueueScreen({super.key});

  void _showErrorDialog(BuildContext context, PendingUpload upload, LocalizationService locService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(locService.t('queue.errorDetails')),
        content: SingleChildScrollView(
          child: Text(
            upload.errorMessage ?? 'Unknown error',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(locService.ok),
          ),
        ],
      ),
    );
  }

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

  String _getUploadStateText(PendingUpload upload, LocalizationService locService) {
    switch (upload.uploadState) {
      case UploadState.pending:
        return upload.attempts > 0 ? ' (Retry ${upload.attempts + 1})' : '';
      case UploadState.creatingChangeset:
        return locService.t('queue.creatingChangeset');
      case UploadState.uploading:
        // Only show time remaining and attempt count if there have been node submission failures
        if (upload.nodeSubmissionAttempts > 0) {
          final timeLeft = upload.timeUntilAutoClose;
          if (timeLeft != null && timeLeft.inMinutes > 0) {
            return '${locService.t('queue.uploading')} (${upload.nodeSubmissionAttempts} attempts, ${timeLeft.inMinutes}m left)';
          } else {
            return '${locService.t('queue.uploading')} (${upload.nodeSubmissionAttempts} attempts)';
          }
        }
        return locService.t('queue.uploading');
      case UploadState.closingChangeset:
        // Only show time remaining if we've had changeset close failures
        if (upload.changesetCloseAttempts > 0) {
          final timeLeft = upload.timeUntilAutoClose;
          if (timeLeft != null && timeLeft.inMinutes > 0) {
            return '${locService.t('queue.closingChangeset')} (${timeLeft.inMinutes}m left)';
          }
        }
        return locService.t('queue.closingChangeset');
      case UploadState.error:
        return locService.t('queue.error');
      case UploadState.complete:
        return locService.t('queue.completing');
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
        
        // Check if queue processing is paused
        final isQueuePaused = appState.offlineMode || appState.pauseQueueProcessing;
        
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
              // Queue processing status indicator
              if (isQueuePaused && appState.pendingCount > 0)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.pause_circle_outline, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              locService.t('queue.processingPaused'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                            Text(
                              appState.offlineMode 
                                  ? locService.t('queue.pausedDueToOffline')
                                  : locService.t('queue.pausedByUser'),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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
                      leading: upload.uploadState == UploadState.error 
                        ? GestureDetector(
                            onTap: () {
                              _showErrorDialog(context, upload, locService);
                            },
                            child: Icon(
                              Icons.error,
                              color: Colors.red,
                            ),
                          )
                        : Icon(
                            Icons.camera_alt,
                            color: _getUploadModeColor(upload.uploadMode),
                          ),
                      title: Text(
                        locService.t('queue.itemWithIndex', params: [(index + 1).toString()]) +
                        _getUploadStateText(upload, locService)
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
                        (upload.uploadState == UploadState.error ? "\n${locService.t('queue.uploadFailedRetry')}" : "")
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (upload.uploadState == UploadState.error)
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              color: Colors.orange,
                              tooltip: locService.t('queue.retryUpload'),
                              onPressed: () {
                                appState.retryUpload(upload);
                              },
                            ),
                          if (upload.uploadState == UploadState.complete)
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