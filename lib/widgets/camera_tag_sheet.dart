import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/osm_camera_node.dart';
import '../app_state.dart';
import 'edit_camera_sheet.dart';

class CameraTagSheet extends StatelessWidget {
  final OsmCameraNode node;

  const CameraTagSheet({super.key, required this.node});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    
    // Check if this camera is editable (not a pending upload)
    final isEditable = !node.tags.containsKey('_pending_upload') || 
                      node.tags['_pending_upload'] != 'true';
    
    void _openEditSheet() {
      Navigator.pop(context); // Close this sheet first
      appState.startEditSession(node);
      
      // Show the edit sheet using a post-frame callback to ensure proper context
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final session = appState.editSession!;
        showModalBottomSheet(
          context: context,
          builder: (_) => EditCameraSheet(session: session),
          showDragHandle: true,
        );
      });
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text('Camera #${node.id}',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...node.tags.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.key,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.value,
                        style: const TextStyle(
                          color: Colors.black54,
                        ),
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isEditable) ...[
                  ElevatedButton.icon(
                    onPressed: _openEditSheet,
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}
