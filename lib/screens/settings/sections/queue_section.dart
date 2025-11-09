import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app_state.dart';
import '../../../services/localization_service.dart';
import '../../../state/settings_state.dart';

class QueueSection extends StatelessWidget {
  const QueueSection({super.key});

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
        
        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.queue),
              title: Text(locService.t('queue.pendingUploads', params: [appState.pendingCount.toString()])),
              subtitle: appState.uploadMode == UploadMode.simulate
                  ? Text(locService.t('queue.simulateModeEnabled'))
                  : appState.uploadMode == UploadMode.sandbox
                      ? Text(locService.t('queue.sandboxMode'))
                      : Text(locService.t('queue.tapToViewQueue')),
              onTap: appState.pendingCount > 0
                  ? () => _showQueueDialog(context)
                  : null,
            ),
            if (appState.pendingCount > 0)
              ListTile(
                leading: const Icon(Icons.clear_all),
                title: Text(locService.t('queue.clearUploadQueue')),
                subtitle: Text(locService.t('queue.removeAllPending', params: [appState.pendingCount.toString()])),
                onTap: () {
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
                },
              ),
          ],
        );
      },
    );
  }

  void _showQueueDialog(BuildContext context) {
    final locService = LocalizationService.instance;
    showDialog(
      context: context,
      builder: (context) => Consumer<AppState>(
        builder: (context, appState, child) => AlertDialog(
          title: Text(locService.t('queue.uploadQueueTitle', params: [appState.pendingCount.toString()])),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: appState.pendingUploads.isEmpty
                ? Center(child: Text(locService.t('queue.queueIsEmpty')))
                : ListView.builder(
                    itemCount: appState.pendingUploads.length,
                    itemBuilder: (context, index) {
                      final upload = appState.pendingUploads[index];
                      return ListTile(
                        leading: Icon(
                          upload.error ? Icons.error : Icons.camera_alt,
                          color: upload.error 
                              ? Colors.red 
                              : _getUploadModeColor(upload.uploadMode),
                        ),
                        title: Text(locService.t('queue.cameraWithIndex', params: [(index + 1).toString()]) +
                            (upload.error ? locService.t('queue.error') : "") +
                            (upload.completing ? locService.t('queue.completing') : "")),
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
                                  if (appState.pendingCount == 0) {
                                    Navigator.pop(context);
                                  }
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(locService.t('actions.close')),
            ),
            if (appState.pendingCount > 1)
              TextButton(
                onPressed: () {
                  appState.clearQueue();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(locService.t('queue.queueCleared'))),
                  );
                },
                child: Text(locService.t('queue.clearAll')),
              ),
          ],
        ),
      ),
    );
  }
}
