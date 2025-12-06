import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/nuclear_reset_service.dart';

/// Non-dismissible error dialog shown when migrations fail and nuclear reset is triggered.
/// Forces user to restart the app by making it impossible to close this dialog.
class NuclearResetDialog extends StatelessWidget {
  final String errorReport;

  const NuclearResetDialog({
    Key? key,
    required this.errorReport,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // Prevent back button from closing dialog
      onWillPop: () async => false,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Migration Error'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Unfortunately we encountered an issue during the app update and had to clear your settings and data.',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 12),
            Text(
              'You will need to:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 4),
            Text('• Log back into OpenStreetMap'),
            Text('• Recreate any custom profiles'),
            Text('• Re-download any offline areas'),
            SizedBox(height: 12),
            Text(
              'Please close and restart the app to continue.',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _copyErrorToClipboard(),
            icon: const Icon(Icons.copy),
            label: const Text('Copy Error'),
          ),
          TextButton.icon(
            onPressed: () => _sendErrorToSupport(),
            icon: const Icon(Icons.email),
            label: const Text('Send to Support'),
          ),
        ],
        // No dismiss button - forces user to restart app
      ),
    );
  }

  Future<void> _copyErrorToClipboard() async {
    await NuclearResetService.copyToClipboard(errorReport);
  }

  Future<void> _sendErrorToSupport() async {
    const supportEmail = 'app@deflock.me';
    const subject = 'DeFlock App Migration Error Report';
    
    // Create mailto URL with pre-filled error report
    final body = Uri.encodeComponent(errorReport);
    final mailtoUrl = 'mailto:$supportEmail?subject=${Uri.encodeComponent(subject)}&body=$body';
    
    try {
      final uri = Uri.parse(mailtoUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      // If email fails, just copy to clipboard as fallback
      await _copyErrorToClipboard();
    }
  }

  /// Show the nuclear reset dialog (non-dismissible)
  static Future<void> show(BuildContext context, Object error, StackTrace? stackTrace) async {
    // Generate error report
    final errorReport = await NuclearResetService.generateErrorReport(error, stackTrace);
    
    // Clear all app data
    await NuclearResetService.clearEverything();
    
    // Show non-dismissible dialog
    await showDialog(
      context: context,
      barrierDismissible: false, // Prevent tap-outside to dismiss
      builder: (context) => NuclearResetDialog(errorReport: errorReport),
    );
  }
}