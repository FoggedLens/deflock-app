import 'package:flutter/material.dart';

class SuspectedLocationProgressDialog extends StatelessWidget {
  final String title;
  final String message;
  final double? progress; // 0.0 to 1.0, null for indeterminate
  final VoidCallback? onCancel;

  const SuspectedLocationProgressDialog({
    super.key,
    required this.title,
    required this.message,
    this.progress,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.help_outline, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          const SizedBox(height: 16),
          if (progress != null)
            LinearProgressIndicator(value: progress)
          else
            const LinearProgressIndicator(),
          const SizedBox(height: 8),
          if (progress != null)
            Text(
              '${(progress! * 100).toInt()}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      actions: [
        if (onCancel != null)
          TextButton(
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
      ],
    );
  }
}