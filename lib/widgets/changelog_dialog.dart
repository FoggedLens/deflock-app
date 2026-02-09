import 'package:flutter/material.dart';
import '../services/version_service.dart';

class ChangelogDialog extends StatelessWidget {
  final String changelogContent;
  
  const ChangelogDialog({
    super.key,
    required this.changelogContent,
  });

  void _onClose(BuildContext context) async {
    // Note: Version tracking is updated by completeVersionChange() after all dialogs
    
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('What\'s New in v${VersionService().version}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              changelogContent,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            Text(
              'Thank you for keeping DeFlock up to date!',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.primary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _onClose(context),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}