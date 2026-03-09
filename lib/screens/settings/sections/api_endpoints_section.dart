import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app_state.dart';
import '../../../models/service_endpoint.dart';
import '../../../state/service_registry.dart';
import '../../../services/localization_service.dart';

class ApiEndpointsSection extends StatelessWidget {
  const ApiEndpointsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) => Consumer<AppState>(
        builder: (context, appState, _) {
          final loc = LocalizationService.instance;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loc.t('settings.apiEndpoints'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                loc.t('settings.apiEndpointsDescription'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              _EndpointRegistryList(
                label: loc.t('settings.apiEndpointRouting'),
                registry: appState.routingRegistry,
              ),
              const SizedBox(height: 16),
              _EndpointRegistryList(
                label: loc.t('settings.apiEndpointNodeSource'),
                registry: appState.overpassRegistry,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EndpointRegistryList extends StatelessWidget {
  final String label;
  final ServiceRegistry<ServiceEndpoint> registry;

  const _EndpointRegistryList({
    required this.label,
    required this.registry,
  });

  bool _isValidHttpsUrl(String url) {
    if (url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService.instance;
    final entries = registry.entries;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        )),
        const SizedBox(height: 8),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: entries.length,
          onReorder: (oldIndex, newIndex) {
            registry.reorder(oldIndex, newIndex);
          },
          itemBuilder: (context, index) {
            final endpoint = entries[index];
            return _EndpointTile(
              key: ValueKey(endpoint.id),
              endpoint: endpoint,
              index: index,
              registry: registry,
              canDelete: !endpoint.isBuiltIn || kDebugMode,
              onToggle: (enabled) {
                // Prevent disabling the last enabled endpoint
                if (!enabled && registry.enabledEntries.length <= 1) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(loc.t('settings.noEnabledEndpoints'))),
                  );
                  return;
                }
                registry.addOrUpdate(endpoint.copyWith(enabled: enabled));
              },
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(loc.t('settings.addEndpoint')),
              onPressed: () => _showAddDialog(context),
            ),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.restore, size: 18),
              label: Text(loc.t('settings.resetToDefaults')),
              onPressed: () => _showResetDialog(context),
            ),
          ],
        ),
      ],
    );
  }

  void _showAddDialog(BuildContext context) {
    final loc = LocalizationService.instance;
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    String? urlError;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(loc.t('settings.addEndpoint')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: loc.t('settings.endpointName'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  labelText: loc.t('settings.endpointUrl'),
                  border: const OutlineInputBorder(),
                  errorText: urlError,
                  hintText: 'https://',
                ),
                keyboardType: TextInputType.url,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(loc.t('actions.cancel')),
            ),
            TextButton(
              onPressed: () {
                final url = urlController.text.trim();
                final name = nameController.text.trim();
                if (!_isValidHttpsUrl(url)) {
                  setState(() => urlError = loc.t('settings.invalidUrl'));
                  return;
                }
                if (name.isEmpty) return;
                final id = 'custom-${DateTime.now().millisecondsSinceEpoch}';
                registry.addOrUpdate(ServiceEndpoint(
                  id: id,
                  name: name,
                  url: url,
                ));
                Navigator.pop(context);
              },
              child: Text(loc.t('actions.ok')),
            ),
          ],
        ),
      ),
    );
  }

  void _showResetDialog(BuildContext context) {
    final loc = LocalizationService.instance;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(loc.t('settings.resetToDefaults')),
        content: Text(loc.t('settings.confirmResetEndpoints')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(loc.t('actions.cancel')),
          ),
          TextButton(
            onPressed: () {
              registry.resetToDefaults();
              Navigator.pop(dialogContext);
            },
            child: Text(loc.t('actions.ok')),
          ),
        ],
      ),
    );
  }
}

class _EndpointTile extends StatelessWidget {
  final ServiceEndpoint endpoint;
  final int index;
  final ServiceRegistry<ServiceEndpoint> registry;
  final bool canDelete;
  final void Function(bool enabled) onToggle;

  const _EndpointTile({
    super.key,
    required this.endpoint,
    required this.index,
    required this.registry,
    required this.canDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        dense: true,
        leading: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle, size: 20),
        ),
        title: Text(
          endpoint.name,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: endpoint.enabled ? null : theme.disabledColor,
          ),
        ),
        subtitle: Text(
          endpoint.url,
          style: theme.textTheme.bodySmall?.copyWith(
            color: endpoint.enabled ? theme.hintColor : theme.disabledColor,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: endpoint.enabled,
              onChanged: onToggle,
            ),
            if (canDelete)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () {
                  try {
                    registry.delete(endpoint.id);
                  } on StateError catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.message)),
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
