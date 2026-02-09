import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/osm_node.dart';
import '../services/localization_service.dart';

/// Information about an OSM editor app
class EditorInfo {
  final String name;
  final String subtitle;
  final IconData icon;
  final String? urlScheme; // null means no custom scheme - go straight to store
  final String? androidStoreUrl;
  final String? iosStoreUrl;
  final bool availableOnAndroid;
  final bool availableOnIOS;
  
  const EditorInfo({
    required this.name,
    required this.subtitle,
    required this.icon,
    this.urlScheme, // Made optional
    this.androidStoreUrl,
    this.iosStoreUrl,
    required this.availableOnAndroid,
    required this.availableOnIOS,
  });
}

class AdvancedEditOptionsSheet extends StatelessWidget {
  final OsmNode node;
  
  const AdvancedEditOptionsSheet({super.key, required this.node});

  /// Mobile editor apps with their platform availability and store URLs
  List<EditorInfo> get _mobileEditors => [
    EditorInfo(
      name: LocalizationService.instance.t('advancedEdit.vespucci'),
      subtitle: LocalizationService.instance.t('advancedEdit.vespucciSubtitle'),
      icon: Icons.android,
      urlScheme: 'josm:/load_and_zoom?select=node${node.id}', // Has documented deep link support
      androidStoreUrl: 'https://play.google.com/store/apps/details?id=de.blau.android',
      availableOnAndroid: true,
      availableOnIOS: false,
    ),
    EditorInfo(
      name: LocalizationService.instance.t('advancedEdit.streetComplete'),
      subtitle: LocalizationService.instance.t('advancedEdit.streetCompleteSubtitle'),
      icon: Icons.place,
      urlScheme: null, // No documented deep link support - go straight to store
      androidStoreUrl: 'https://play.google.com/store/apps/details?id=de.westnordost.streetcomplete',
      availableOnAndroid: true,
      availableOnIOS: false,
    ),
    EditorInfo(
      name: LocalizationService.instance.t('advancedEdit.everyDoor'),
      subtitle: LocalizationService.instance.t('advancedEdit.everyDoorSubtitle'),
      icon: Icons.map,
      urlScheme: null, // No documented deep link support - go straight to store
      androidStoreUrl: 'https://play.google.com/store/apps/details?id=info.zverev.ilya.every_door',
      iosStoreUrl: 'https://apps.apple.com/app/every-door/id1621945342',
      availableOnAndroid: true,
      availableOnIOS: true,
    ),
    EditorInfo(
      name: LocalizationService.instance.t('advancedEdit.goMap'),
      subtitle: LocalizationService.instance.t('advancedEdit.goMapSubtitle'),
      icon: Icons.phone_iphone,
      urlScheme: null, // No documented deep link support - go straight to store
      iosStoreUrl: 'https://apps.apple.com/app/go-map/id592990211',
      availableOnAndroid: false,
      availableOnIOS: true,
    ),
  ];

  /// Web editor apps (always available on all platforms)
  List<EditorInfo> get _webEditors => [
    EditorInfo(
      name: LocalizationService.instance.t('advancedEdit.iDEditor'),
      subtitle: LocalizationService.instance.t('advancedEdit.iDEditorSubtitle'),
      icon: Icons.public,
      urlScheme: 'https://www.openstreetmap.org/edit?editor=id&node=${node.id}',
      availableOnAndroid: true,
      availableOnIOS: true,
    ),
    EditorInfo(
      name: LocalizationService.instance.t('advancedEdit.rapidEditor'),
      subtitle: LocalizationService.instance.t('advancedEdit.rapidEditorSubtitle'),
      icon: Icons.speed,
      urlScheme: 'https://rapideditor.org/edit#map=19/0/0&nodes=${node.id}',
      availableOnAndroid: true,
      availableOnIOS: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final locService = LocalizationService.instance;
    
    // Filter mobile editors based on current platform
    final availableMobileEditors = _mobileEditors.where((editor) {
      if (Platform.isAndroid) return editor.availableOnAndroid;
      if (Platform.isIOS) return editor.availableOnIOS;
      return false; // Other platforms don't have mobile editors
    }).toList();
    
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              locService.t('advancedEdit.title'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              locService.t('advancedEdit.subtitle'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 16),
            
            // Web Editors Section
            Text(
              locService.t('advancedEdit.webEditors'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ..._webEditors.map((editor) => _buildEditorTile(context, editor)),
            
            // Mobile Editors Section (only show if there are available editors)
            if (availableMobileEditors.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                locService.t('advancedEdit.mobileEditors'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...availableMobileEditors.map((editor) => _buildEditorTile(context, editor)),
            ],
            
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(locService.t('actions.close')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorTile(BuildContext context, EditorInfo editor) {
    return ListTile(
      leading: Icon(editor.icon, size: 24),
      title: Text(editor.name),
      subtitle: Text(editor.subtitle),
      trailing: const Icon(Icons.launch, size: 18),
      onTap: () => _launchEditor(context, editor),
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
    );
  }

  void _launchEditor(BuildContext context, EditorInfo editor) async {
    Navigator.pop(context); // Close the sheet first
    
    // If app has a custom URL scheme, try to open it
    if (editor.urlScheme != null) {
      try {
        final uri = Uri.parse(editor.urlScheme!);
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (launched) return; // Success - app opened
      } catch (e) {
        // App launch failed - continue to app store
      }
    }
    
    // No custom scheme or app launch failed - redirect to app store
    if (!context.mounted) return;
    await _redirectToAppStore(context, editor);
  }

  Future<void> _redirectToAppStore(BuildContext context, EditorInfo editor) async {
    final locService = LocalizationService.instance;
    
    try {
      if (Platform.isAndroid && editor.androidStoreUrl != null) {
        // Try native Play Store first, then web fallback
        final packageName = _extractAndroidPackageName(editor.androidStoreUrl!);
        if (packageName != null) {
          final marketUri = Uri.parse('market://details?id=$packageName');
          try {
            final launched = await launchUrl(marketUri, mode: LaunchMode.externalApplication);
            if (launched) return;
          } catch (e) {
            // Fall back to web Play Store
          }
        }
        
        // Web Play Store fallback
        final webStoreUri = Uri.parse(editor.androidStoreUrl!);
        await launchUrl(webStoreUri, mode: LaunchMode.externalApplication);
        return;
      } else if (Platform.isIOS && editor.iosStoreUrl != null) {
        // iOS App Store
        final iosStoreUri = Uri.parse(editor.iosStoreUrl!);
        await launchUrl(iosStoreUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (e) {
      // Fall through to show error message
    }
    
    // Could not open app or store - show error message
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(locService.t('advancedEdit.couldNotOpenEditor'))),
      );
    }
  }
  
  /// Extract Android package name from Play Store URL for market:// scheme
  String? _extractAndroidPackageName(String playStoreUrl) {
    final uri = Uri.tryParse(playStoreUrl);
    if (uri == null) return null;
    
    // Extract from "id=" parameter in Play Store URLs
    return uri.queryParameters['id'];
  }
}