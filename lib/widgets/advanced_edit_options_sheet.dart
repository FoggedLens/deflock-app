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
            _buildEditorTile(
              context: context,
              icon: Icons.public,
              title: locService.t('advancedEdit.iDEditor'),
              subtitle: locService.t('advancedEdit.iDEditorSubtitle'),
              onTap: () => _launchEditor(context, 'https://www.openstreetmap.org/edit?editor=id&node=${node.id}'),
            ),
            _buildEditorTile(
              context: context,
              icon: Icons.speed,
              title: locService.t('advancedEdit.rapidEditor'),
              subtitle: locService.t('advancedEdit.rapidEditorSubtitle'),
              onTap: () => _launchEditor(context, 'https://rapideditor.org/edit#map=19/0/0&nodes=${node.id}'),
            ),
            
            const SizedBox(height: 16),
            
            // Mobile Editors Section
            Text(
              locService.t('advancedEdit.mobileEditors'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            
            if (Platform.isAndroid) ...[
              _buildEditorTile(
                context: context,
                icon: Icons.android,
                title: locService.t('advancedEdit.vespucci'),
                subtitle: locService.t('advancedEdit.vespucciSubtitle'),
                onTap: () => _launchEditor(context, 'vespucci://edit?node=${node.id}'),
              ),
              _buildEditorTile(
                context: context,
                icon: Icons.place,
                title: locService.t('advancedEdit.streetComplete'),
                subtitle: locService.t('advancedEdit.streetCompleteSubtitle'),
                onTap: () => _launchEditor(context, 'streetcomplete://quest?node=${node.id}'),
              ),
              _buildEditorTile(
                context: context,
                icon: Icons.map,
                title: locService.t('advancedEdit.everyDoor'),
                subtitle: locService.t('advancedEdit.everyDoorSubtitle'),
                onTap: () => _launchEditor(context, 'everydoor://edit?node=${node.id}'),
              ),
            ],
            
            if (Platform.isIOS) ...[
              _buildEditorTile(
                context: context,
                icon: Icons.phone_iphone,
                title: locService.t('advancedEdit.goMap'),
                subtitle: locService.t('advancedEdit.goMapSubtitle'),
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
    final locService = LocalizationService.instance;
    Navigator.pop(context); // Close the sheet first
    
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(locService.t('advancedEdit.couldNotOpenEditor'))),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(locService.t('advancedEdit.couldNotOpenEditor'))),
        );
      }
    }
  }
}