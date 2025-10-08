import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/localization_service.dart';

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
          padding: const EdgeInsets.all(16),
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
              const SizedBox(height: 32),
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
        const SizedBox(height: 8),
        _buildLinkText(context, 'Donate', 'https://deflock.me/donate'),
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
}