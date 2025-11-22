import 'package:flutter/material.dart';
import '../services/localization_service.dart';

class DownloadStartedDialog extends StatelessWidget {
  const DownloadStartedDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.download_for_offline, color: Colors.green),
              const SizedBox(width: 10),
              Text(locService.t('downloadStarted.title')),
            ],
          ),
          content: Text(locService.t('downloadStarted.message')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(locService.t('downloadStarted.ok')),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/settings/offline');
              },
              child: Text(locService.t('downloadStarted.viewProgress')),
            ),
          ],
        );
      },
    );
  }
}