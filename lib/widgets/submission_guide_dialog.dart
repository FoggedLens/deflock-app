import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/changelog_service.dart';
import '../services/localization_service.dart';

class SubmissionGuideDialog extends StatefulWidget {
  const SubmissionGuideDialog({super.key, this.showDontShowAgain = true});

  final bool showDontShowAgain;

  @override
  State<SubmissionGuideDialog> createState() => _SubmissionGuideDialogState();
}

class _SubmissionGuideDialogState extends State<SubmissionGuideDialog> {
  bool _dontShowAgain = false;
  bool _isInitialized = false;

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentState();
  }

  Future<void> _loadCurrentState() async {
    if (!widget.showDontShowAgain) {
      // When manually opened, show the actual current state
      final hasSeenSubmissionGuide = await ChangelogService().hasSeenSubmissionGuide();
      setState(() {
        _dontShowAgain = hasSeenSubmissionGuide;
        _isInitialized = true;
      });
    } else {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  void _onClose() async {
    if (_dontShowAgain && widget.showDontShowAgain) {
      await ChangelogService().markSubmissionGuideSeen();
    }
    
    if (mounted) {
      Navigator.of(context).pop(true); // Return true to indicate "proceed with submission"
    }
  }

  @override
  Widget build(BuildContext context) {
    final locService = LocalizationService.instance;
    
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) => AlertDialog(
        title: Text(locService.t('submissionGuide.title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Scrollable content
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      locService.t('submissionGuide.description'),
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        locService.t('submissionGuide.bestPractices'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      locService.t('submissionGuide.placementNote'),
                      style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      locService.t('submissionGuide.moreInfo'),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    // Resource links row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildLinkButton(
                          locService.t('submissionGuide.identificationGuide'), 
                          'https://deflock.me/identify'
                        ),
                        _buildLinkButton(
                          locService.t('submissionGuide.osmWiki'), 
                          'https://wiki.openstreetmap.org/wiki/Tag:man_made%3Dsurveillance'
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Always visible checkbox, but disabled when manually opened
            if (_isInitialized)
              Row(
                children: [
                  Checkbox(
                    value: _dontShowAgain,
                    onChanged: widget.showDontShowAgain ? (value) {
                      setState(() {
                        _dontShowAgain = value ?? false;
                      });
                    } : null,
                  ),
                  Expanded(
                    child: Text(
                      locService.t('submissionGuide.dontShowAgain'),
                      style: TextStyle(
                        fontSize: 13,
                        color: widget.showDontShowAgain 
                          ? null 
                          : Theme.of(context).disabledColor,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Cancel - just close dialog without marking as seen, return false to cancel submission
              Navigator.of(context).pop(false);
            },
            child: Text(locService.cancel),
          ),
          TextButton(
            onPressed: _onClose,
            child: Text(locService.t('submissionGuide.gotIt')),
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
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
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