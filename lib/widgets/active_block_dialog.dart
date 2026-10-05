import 'package:flutter/material.dart';
import '../services/localization_service.dart';

/// Dialog shown whenever a check finds that the user's OSM account has an
/// active block. Unlike the unread-notifications dialog, this has no
/// "don't show again" option and is shown every time a check finds a block.
class ActiveBlockDialog extends StatelessWidget {
  final VoidCallback onViewDetails;
  final VoidCallback onDismiss;

  const ActiveBlockDialog({
    super.key,
    required this.onViewDetails,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final locService = LocalizationService.instance;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.block,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(locService.t('auth.activeBlockTitle')),
          ),
        ],
      ),
      content: Text(locService.t('auth.activeBlockMessage')),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            onDismiss();
          },
          child: Text(locService.t('actions.dismiss')),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            onViewDetails();
          },
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(locService.t('auth.viewBlockDetails')),
        ),
      ],
    );
  }
}
