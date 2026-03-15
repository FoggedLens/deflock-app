import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../dev_config.dart';
import '../services/localization_service.dart';
import '../services/nuclear_reset_service.dart';
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
              // About OpenStreetMap section
              _buildAboutOSMSection(context),
              const SizedBox(height: 24),
              // Information dialogs section
              _buildDialogButtons(context),
              const SizedBox(height: 24),
              _buildHelpLinks(context),
              
              // Dev-only nuclear reset button at very bottom
              if (kDebugMode || kEnableDevelopmentModes) ...[
                const SizedBox(height: 32),
                _buildDevNuclearResetButton(context),
                const SizedBox(height: 16),
              ],
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
        _buildLinkText(context, 'Report issue with OSM base map', 'https://www.openstreetmap.org/fixthemap'),
        const SizedBox(height: 8),
        _buildLinkText(context, 'DeFlock Discord', 'https://discord.gg/aV7v4R3sKT'),
        const SizedBox(height: 8),
        _buildLinkText(context, 'Source Code', 'https://github.com/FoggedLens/deflock-app'),
        const SizedBox(height: 8),
        _buildLinkText(context, 'Contact', 'https://deflock.me/contact'),
      ],
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

  Widget _buildAboutOSMSection(BuildContext context) {
    final locService = LocalizationService.instance;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              locService.t('auth.aboutOSM'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              locService.t('auth.aboutOSMDescription'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _launchUrl('https://openstreetmap.org', context),
                icon: const Icon(Icons.open_in_new),
                label: Text(locService.t('auth.visitOSM')),
              ),
            ),
          ],
        ),
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

  /// Dev-only nuclear reset button (only visible in debug mode)
  Widget _buildDevNuclearResetButton(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.developer_mode,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Developer Tools',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'These tools are only available in debug mode for development and troubleshooting.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showNuclearResetConfirmation(context),
                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                  label: const Text(
                    'Nuclear Reset (Clear All Data)',
                    style: TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Show confirmation dialog for nuclear reset
  Future<void> _showNuclearResetConfirmation(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Nuclear Reset'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will completely clear ALL app data:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 12),
            Text('• All settings and preferences'),
            Text('• OAuth login credentials'),
            Text('• Custom profiles and operators'),
            Text('• Upload queue and cached data'),
            Text('• Downloaded offline areas'),
            Text('• Everything else'),
            SizedBox(height: 16),
            Text(
              'The app will behave exactly like a fresh install after this operation.',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.red,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'This action cannot be undone.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Nuclear Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await _performNuclearReset(context);
    }
  }

  /// Perform the nuclear reset operation
  Future<void> _performNuclearReset(BuildContext context) async {
    // Show progress dialog
    if (!context.mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Clearing all app data...'),
          ],
        ),
      ),
    );

    try {
      // Perform the nuclear reset
      await NuclearResetService.clearEverything();
      
      if (!context.mounted) return;
      
      // Close progress dialog
      Navigator.of(context).pop();
      
      // Show completion dialog
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Reset Complete'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'All app data has been cleared successfully.',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 12),
              Text(
                'Please close and restart the app to continue with a fresh state.',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      
      // Close progress dialog if it's still open
      Navigator.of(context).pop();
      
      // Show error dialog
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error, color: Colors.red),
              SizedBox(width: 8),
              Text('Reset Failed'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'An error occurred during the nuclear reset:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              Text(
                e.toString(),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Some data may have been partially cleared. You may want to manually clear app data through device settings.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

}