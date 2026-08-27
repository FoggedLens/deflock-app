import 'package:flutter/material.dart';
import '../services/localization_service.dart';

/// Dialog shown once per session when the user has unread OSM messages
/// and/or unread changeset comments, prompting them to view their OSM
/// account details.
class UnreadNotificationsDialog extends StatelessWidget {
  final VoidCallback onView;
  final VoidCallback onDismiss;

  const UnreadNotificationsDialog({
    super.key,
    required this.onView,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final locService = LocalizationService.instance;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.notifications_active_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(locService.t('auth.unreadNotificationsTitle')),
          ),
        ],
      ),
      content: Text(locService.t('auth.unreadNotificationsMessage')),
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
            onView();
          },
          icon: const Icon(Icons.arrow_forward, size: 18),
          label: Text(locService.t('auth.unreadNotificationsView')),
        ),
      ],
    );
  }
}
