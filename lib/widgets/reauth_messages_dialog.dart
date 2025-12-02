import 'package:flutter/material.dart';
import '../services/localization_service.dart';

/// Dialog to prompt user to re-authenticate for message notifications
class ReauthMessagesDialog extends StatelessWidget {
  final VoidCallback onReauth;
  final VoidCallback onDismiss;

  const ReauthMessagesDialog({
    super.key,
    required this.onReauth,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final locService = LocalizationService.instance;
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.message_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(locService.t('auth.reauthRequired')),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(locService.t('auth.reauthExplanation')),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    locService.t('auth.reauthBenefit'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            onDismiss();
          },
          child: Text(locService.t('auth.reauthLater')),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            onReauth();
          },
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(locService.t('auth.reauthNow')),
        ),
      ],
    );
  }
}