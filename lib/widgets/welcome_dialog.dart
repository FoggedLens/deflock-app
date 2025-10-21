import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/changelog_service.dart';
import '../services/localization_service.dart';

class WelcomeDialog extends StatefulWidget {
  const WelcomeDialog({super.key});

  @override
  State<WelcomeDialog> createState() => _WelcomeDialogState();
}

class _WelcomeDialogState extends State<WelcomeDialog> {
  bool _dontShowAgain = false;

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _onClose() async {
    if (_dontShowAgain) {
      await ChangelogService().markWelcomeSeen();
    }
    
    // Always update version tracking when closing welcome dialog
    await ChangelogService().updateLastSeenVersion();
    
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final locService = LocalizationService.instance;
    
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) => AlertDialog(
        title: Text(locService.t('welcome.title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                locService.t('welcome.description'),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Text(
                locService.t('welcome.mission'),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Text(
                locService.t('welcome.privacy'),
                style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 12),
              Text(
                locService.t('welcome.tileNote'),
                style: const TextStyle(fontSize: 13, color: Colors.orange),
              ),
              const SizedBox(height: 16),
              Text(
                locService.t('welcome.moreInfo'),
                style: const TextStyle(fontSize: 13),
              ),
            const SizedBox(height: 16),
            // Quick links row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildLinkButton('Website', 'https://deflock.me'),
                _buildLinkButton('GitHub', 'https://github.com/FoggedLens/deflock-app'),
                _buildLinkButton('Discord', 'https://discord.gg/aV7v4R3sKT'),
                _buildLinkButton('Donate', 'https://deflock.me/donate'),
              ],
            ),
            const SizedBox(height: 16),
            // Don't show again checkbox
            Row(
              children: [
                Checkbox(
                  value: _dontShowAgain,
                  onChanged: (value) {
                    setState(() {
                      _dontShowAgain = value ?? false;
                    });
                  },
                ),
                Expanded(
                  child: Text(
                    locService.t('welcome.dontShowAgain'),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
        actions: [
          TextButton(
            onPressed: _onClose,
            child: Text(locService.t('welcome.getStarted')),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkButton(String text, String url) {
    return Flexible(
      child: GestureDetector(
        onTap: () => _launchUrl(url),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}