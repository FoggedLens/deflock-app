import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/osm_node.dart';
import '../app_state.dart';
import '../services/localization_service.dart';
import 'advanced_edit_options_sheet.dart';

class NodeTagSheet extends StatelessWidget {
  final OsmNode node;
  final VoidCallback? onEditPressed;

  const NodeTagSheet({super.key, required this.node, this.onEditPressed});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final appState = context.watch<AppState>();
        final locService = LocalizationService.instance;
        
        // Check if this device is editable (not a pending upload, pending edit, or pending deletion)
        final isEditable = (!node.tags.containsKey('_pending_upload') || 
                           node.tags['_pending_upload'] != 'true') &&
                          (!node.tags.containsKey('_pending_edit') || 
                           node.tags['_pending_edit'] != 'true') &&
                          (!node.tags.containsKey('_pending_deletion') || 
                           node.tags['_pending_deletion'] != 'true');
        
        void _openEditSheet() {
          if (onEditPressed != null) {
            onEditPressed!(); // Use callback if provided
          } else {
            // Fallback behavior
            Navigator.pop(context); // Close this sheet first
            appState.startEditSession(node); // HomeScreen will auto-show the edit sheet
          }
        }

        void _deleteNode() async {
          final shouldDelete = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text(locService.t('node.confirmDeleteTitle')),
                content: Text(locService.t('node.confirmDeleteMessage', params: [node.id.toString()])),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(locService.cancel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: Text(locService.t('actions.delete')),
                  ),
                ],
              );
            },
          );

          if (shouldDelete == true && context.mounted) {
            Navigator.pop(context); // Close this sheet first
            appState.deleteNode(node);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(locService.t('node.deleteQueuedForUpload'))),
            );
          }
        }

        void _viewOnOSM() async {
          final url = 'https://www.openstreetmap.org/node/${node.id}';
          try {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not open OSM website')),
                );
              }
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not open OSM website')),
              );
            }
          }
        }

        void _openAdvancedEdit() {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (context) => AdvancedEditOptionsSheet(node: node),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    locService.t('node.title').replaceAll('{}', node.id.toString()),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  ...node.tags.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.key,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              e.value,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                              ),
                              softWrap: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // First row: View and Advanced buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _viewOnOSM(),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('View on OSM'),
                      ),
                      const SizedBox(width: 8),
                      if (isEditable) ...[
                        OutlinedButton.icon(
                          onPressed: _openAdvancedEdit,
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('Advanced'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 36),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Second row: Edit, Delete, and Close buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (isEditable) ...[
                        ElevatedButton.icon(
                          onPressed: _openEditSheet,
                          icon: const Icon(Icons.edit, size: 18),
                          label: Text(locService.edit),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 36),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _deleteNode,
                          icon: const Icon(Icons.delete, size: 18),
                          label: Text(locService.t('actions.delete')),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            foregroundColor: Colors.red,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(locService.t('actions.close')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}