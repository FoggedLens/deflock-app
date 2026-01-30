import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/localization_service.dart';

/// Dialog offering users a choice between creating a custom profile or importing from website
class ProfileAddChoiceDialog extends StatelessWidget {
  const ProfileAddChoiceDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        
        return AlertDialog(
          title: Text(locService.t('profiles.addProfileChoice')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(locService.t('profiles.addProfileChoiceMessage')),
              const SizedBox(height: 16),
              // Create custom profile option
              Card(
                child: ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: Text(locService.t('profiles.createCustomProfile')),
                  subtitle: Text(locService.t('profiles.createCustomProfileDescription')),
                  onTap: () => Navigator.of(context).pop('create'),
                ),
              ),
              const SizedBox(height: 8),
              // Import from website option
              Card(
                child: ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(locService.t('profiles.importFromWebsite')),
                  subtitle: Text(locService.t('profiles.importFromWebsiteDescription')),
                  onTap: () => _openWebsite(context),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(locService.cancel),
            ),
          ],
        );
      },
    );
  }

  void _openWebsite(BuildContext context) async {
    const url = 'https://deflock.me/identify';
    
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication, // Force external browser
        );
        // Close dialog after opening website
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      } else {
        if (context.mounted) {
          _showErrorSnackBar(context, 'Unable to open website');
        }
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackBar(context, 'Error opening website: $e');
      }
    }
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}