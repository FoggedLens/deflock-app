import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/osm_node.dart';
import '../services/localization_service.dart';

class AdvancedEditOptionsSheet extends StatelessWidget {
  final OsmNode node;
  
  const AdvancedEditOptionsSheet({super.key, required this.node});

  @override
  Widget build(BuildContext context) {
    final locService = LocalizationService.instance;
    
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Advanced Editing Options',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'These editors offer more advanced features for complex edits.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 16),
            
            // Web Editors Section
            Text(
              'Web Editors',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _buildEditorTile(
              context: context,
              icon: Icons.public,
              title: 'iD Editor',
              subtitle: 'Full-featured web editor - always works',
              onTap: () => _launchEditor(context, 'https://www.openstreetmap.org/edit?editor=id&node=${node.id}'),
            ),
            _buildEditorTile(
              context: context,
              icon: Icons.speed,
              title: 'RapiD Editor',
              subtitle: 'AI-assisted editing with Facebook data',
              onTap: () => _launchEditor(context, 'https://rapideditor.org/edit#map=19/0/0&nodes=${node.id}'),
            ),
            
            const SizedBox(height: 16),
            
            // Mobile Editors Section
            Text(
              'Mobile Editors',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            
            if (Platform.isAndroid) ...[
              _buildEditorTile(
                context: context,
                icon: Icons.android,
                title: 'Vespucci',
                subtitle: 'Advanced Android OSM editor',
                onTap: () => _launchEditor(context, 'vespucci://edit?node=${node.id}'),
              ),
              _buildEditorTile(
                context: context,
                icon: Icons.place,
                title: 'StreetComplete',
                subtitle: 'Survey-based mapping app',
                onTap: () => _launchEditor(context, 'streetcomplete://quest?node=${node.id}'),
              ),
              _buildEditorTile(
                context: context,
                icon: Icons.map,
                title: 'EveryDoor',
                subtitle: 'Fast POI editing',
                onTap: () => _launchEditor(context, 'everydoor://edit?node=${node.id}'),
              ),
            ],
            
            if (Platform.isIOS) ...[
              _buildEditorTile(
                context: context,
                icon: Icons.phone_iphone,
                title: 'Go Map!!',
                subtitle: 'iOS OSM editor',
                onTap: () => _launchEditor(context, 'gomaposm://edit?node=${node.id}'),
              ),
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

  Widget _buildEditorTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, size: 24),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.launch, size: 18),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
    );
  }

  void _launchEditor(BuildContext context, String url) async {
    Navigator.pop(context); // Close the sheet first
    
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open $url - app may not be installed')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open editor - app may not be installed')),
        );
      }
    }
  }
}