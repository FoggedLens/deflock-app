import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/localization_service.dart';
import '../widgets/welcome_dialog.dart';
import '../widgets/submission_guide_dialog.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _launchUrl(String url, BuildContext context) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open URL: $url'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locService = LocalizationService.instance;
    
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) => Scaffold(
        appBar: AppBar(
          title: Text(locService.t('settings.aboutThisApp')),
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16, 
            16, 
            16, 
            16 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                locService.t('about.title'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: 16),
              Text(
                locService.t('about.description'),
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: 16),
              Text(
                locService.t('about.features'),
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: 16),
              Text(
                locService.t('about.initiative'),
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: 24),
              Text(
                locService.t('about.footer'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Information dialogs section
              _buildDialogButtons(context),
              const SizedBox(height: 24),
              _buildHelpLinks(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHelpLinks(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLinkText(context, 'About DeFlock', 'https://deflock.me/about'),
        const SizedBox(height: 8),
        _buildLinkText(context, 'Privacy Policy', 'https://deflock.me/privacy'),
        const SizedBox(height: 8),
        _buildLinkText(context, 'DeFlock Discord', 'https://discord.gg/aV7v4R3sKT'),
        const SizedBox(height: 8),
        _buildLinkText(context, 'Source Code', 'https://github.com/FoggedLens/deflock-app'),
        const SizedBox(height: 8),
        _buildLinkText(context, 'Contact', 'https://deflock.me/contact'),
        const SizedBox(height: 24),
        
        // Divider for account management section
        Divider(
          color: Theme.of(context).dividerColor.withOpacity(0.3),
        ),
        const SizedBox(height: 16),
        
        // Account deletion link (less prominent)
        _buildAccountDeletionLink(context),
      ],
    );
  }

  Widget _buildAccountDeletionLink(BuildContext context) {
    final locService = LocalizationService.instance;
    
    return GestureDetector(
      onTap: () => _showDeleteAccountDialog(context, locService),
      child: Text(
        locService.t('auth.deleteAccount'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.error.withOpacity(0.7),
          decoration: TextDecoration.underline,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context, LocalizationService locService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(locService.t('auth.deleteAccount')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(locService.t('auth.deleteAccountExplanation')),
            const SizedBox(height: 12),
            Text(
              locService.t('auth.deleteAccountWarning'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(locService.t('actions.cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _launchUrl('https://www.openstreetmap.org/account/deletion', context);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(locService.t('auth.goToOSM')),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkText(BuildContext context, String text, String url) {
    return GestureDetector(
      onTap: () => _launchUrl(url, context),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildDialogButtons(BuildContext context) {
    final locService = LocalizationService.instance;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Welcome Message button
        OutlinedButton.icon(
          onPressed: () {
            showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (context) => const WelcomeDialog(showDontShowAgain: false),
            );
          },
          icon: const Icon(Icons.waving_hand_outlined),
          label: Text(locService.t('about.showWelcome')),
        ),
        const SizedBox(height: 8),
        // Submission Guide button
        OutlinedButton.icon(
          onPressed: () {
            showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (context) => const SubmissionGuideDialog(showDontShowAgain: false),
            );
          },
          icon: const Icon(Icons.info_outline),
          label: Text(locService.t('about.showSubmissionGuide')),
        ),
        const SizedBox(height: 8),
        // Release Notes button
        OutlinedButton.icon(
          onPressed: () {
            Navigator.pushNamed(context, '/settings/release-notes');
          },
          icon: const Icon(Icons.article_outlined),
          label: Text(locService.t('about.viewReleaseNotes')),
        ),
      ],
    );
  }


}