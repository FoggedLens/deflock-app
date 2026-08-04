import 'dart:async';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../dev_config.dart';
import '../services/localization_service.dart';

/// Applies a queue-pausing settings change (enabling offline mode or pausing
/// the upload queue), but if there's an in-flight submission (a queue item
/// that has already opened a changeset and hasn't closed it yet), first
/// shows a non-dismissible-by-tap-outside dialog explaining that the
/// submission needs to finish. Once it completes, a brief confirmation is
/// shown before the dialog auto-closes and the setting takes effect.
///
/// If nothing is in-flight, [applyChange] is invoked immediately with no
/// dialog shown at all.
///
/// The dialog can also be dismissed early by the user tapping "View in
/// Queue", in case something is stuck (e.g. a failed/erroring item) — this
/// lets the user navigate to the queue screen to investigate/clear it out,
/// rather than getting stuck waiting indefinitely.
Future<void> applyQueueSettingChangeRespectingInFlightUploads({
  required BuildContext context,
  required AppState appState,
  required Future<void> Function() applyChange,
}) async {
  if (!appState.hasInFlightUploads) {
    await applyChange();
    return;
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => InFlightUploadWaitDialog(
      onAllComplete: () {
        // Fire and forget - the dialog doesn't need to await this.
        applyChange();
      },
    ),
  );
}

class InFlightUploadWaitDialog extends StatefulWidget {
  /// Called exactly once, as soon as no queue items are actively processing.
  final VoidCallback onAllComplete;

  const InFlightUploadWaitDialog({super.key, required this.onAllComplete});

  @override
  State<InFlightUploadWaitDialog> createState() => _InFlightUploadWaitDialogState();
}

class _InFlightUploadWaitDialogState extends State<InFlightUploadWaitDialog> {
  bool _completed = false;
  bool _appliedChange = false;
  Timer? _autoCloseTimer;
  late final AppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = AppState.instance;
    _appState.addListener(_onAppStateChanged);
    // Handle the (unlikely) race where the in-flight upload finishes between
    // the initial check and this dialog actually mounting.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onAppStateChanged());
  }

  void _onAppStateChanged() {
    if (!mounted || _completed) return;
    if (_appState.hasInFlightUploads) return;

    setState(() {
      _completed = true;
    });

    if (!_appliedChange) {
      _appliedChange = true;
      widget.onAllComplete();
    }

    _autoCloseTimer = Timer(kInFlightUploadCompleteDisplayDuration, () {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    });
  }

  @override
  void dispose() {
    _appState.removeListener(_onAppStateChanged);
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  void _viewInQueue() {
    Navigator.of(context, rootNavigator: true).pop();
    Navigator.of(context).pushNamed('/settings/queue');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;

        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: Row(
              children: [
                Icon(
                  _completed ? Icons.check_circle : Icons.cloud_upload,
                  color: _completed ? Colors.green : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _completed
                        ? locService.t('queue.inFlightCompleteTitle')
                        : locService.t('queue.inFlightWaitTitle'),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _completed
                      ? locService.t('queue.inFlightCompleteMessage')
                      : locService.t('queue.inFlightWaitMessage'),
                ),
                const SizedBox(height: 20),
                Center(
                  child: _completed
                      ? const Icon(Icons.check_circle, size: 40, color: Colors.green)
                      : const CircularProgressIndicator(),
                ),
              ],
            ),
            actions: [
              if (!_completed)
                TextButton(
                  onPressed: _viewInQueue,
                  child: Text(locService.t('node.viewInQueue')),
                ),
            ],
          ),
        );
      },
    );
  }
}
