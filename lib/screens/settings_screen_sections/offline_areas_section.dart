import 'package:flutter/material.dart';
import '../../services/offline_area_service.dart';
import '../../services/offline_areas/offline_area_models.dart';
import '../../services/localization_service.dart';

class OfflineAreasSection extends StatefulWidget {
  const OfflineAreasSection({super.key});

  @override
  State<OfflineAreasSection> createState() => _OfflineAreasSectionState();
}

class _OfflineAreasSectionState extends State<OfflineAreasSection> {
  OfflineAreaService get service => OfflineAreaService();

  @override
  void initState() {
    super.initState();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {});
      return true;
    });
  }

  void _showRefreshDialog(OfflineArea area) {
    showDialog(
      context: context,
      builder: (context) => _RefreshAreaDialog(
        area: area,
        onRefresh: (refreshTiles, refreshNodes) {
          try {
            // ignore: unawaited_futures
            service.refreshArea(
              id: area.id,
              refreshTiles: refreshTiles,
              refreshNodes: refreshNodes,
              onProgress: (progress) => setState(() {}),
              onComplete: (status) => setState(() {}),
            );
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(LocalizationService.instance.t('offlineAreas.refreshStarted')),
              ),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(LocalizationService.instance.t('offlineAreas.refreshFailed', params: [e.toString()])),
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        final areas = service.offlineAreas;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              locService.t('offlineAreas.title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (areas.isEmpty)
              ListTile(
                leading: const Icon(Icons.download_for_offline),
                title: Text(locService.t('offlineAreas.noAreasTitle')),
                subtitle: Text(locService.t('offlineAreas.noAreasSubtitle')),
              )
            else
              ...areas.map((area) {
            String diskStr = area.sizeBytes > 0
                ? area.sizeBytes > 1024 * 1024
                    ? "${(area.sizeBytes / (1024 * 1024)).toStringAsFixed(2)} ${locService.t('offlineAreas.megabytes')}"
                    : "${(area.sizeBytes / 1024).toStringAsFixed(1)} ${locService.t('offlineAreas.kilobytes')}"
                : '--';
                
            String subtitle = '${locService.t('offlineAreas.provider')}: ${area.tileProviderDisplay}\n' +
                '${locService.t('offlineAreas.maxZoom')}: Z${area.maxZoom}' + '\n' +
                '${locService.t('offlineAreas.latitude')}: ${area.bounds.southWest.latitude.toStringAsFixed(3)}, ${area.bounds.southWest.longitude.toStringAsFixed(3)}\n' +
                '${locService.t('offlineAreas.latitude')}: ${area.bounds.northEast.latitude.toStringAsFixed(3)}, ${area.bounds.northEast.longitude.toStringAsFixed(3)}';
                
            if (area.status == OfflineAreaStatus.downloading) {
              subtitle += '\n${locService.t('offlineAreas.tiles')}: ${area.tilesDownloaded} / ${area.tilesTotal}';
            } else {
              subtitle += '\n${locService.t('offlineAreas.tiles')}: ${area.tilesTotal}';
            }
            subtitle += '\n${locService.t('offlineAreas.size')}: $diskStr';
            subtitle += '\n${locService.t('offlineAreas.nodes')}: ${area.nodes.length}';
        return Card(
          child: ListTile(
            leading: Icon(area.status == OfflineAreaStatus.complete
                ? Icons.cloud_done
                : area.status == OfflineAreaStatus.error
                    ? Icons.error
                    : Icons.download_for_offline),
            title: Row(
              children: [
                Expanded(
                  child: Text(area.name.isNotEmpty
                      ? area.name
                      : locService.t('offlineAreas.areaIdFallback', params: [area.id.substring(0, 6)])),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: locService.t('offlineAreas.renameArea'),
                    onPressed: () async {
                      String? newName = await showDialog<String>(
                        context: context,
                        builder: (ctx) {
                          final ctrl = TextEditingController(text: area.name);
                          return AlertDialog(
                            title: Text(locService.t('offlineAreas.renameAreaDialogTitle')),
                            content: TextField(
                              controller: ctrl,
                              maxLength: 40,
                              decoration: InputDecoration(labelText: locService.t('offlineAreas.areaNameLabel')),
                              autofocus: true,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: Text(locService.t('actions.cancel')),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(ctx, ctrl.text.trim());
                                },
                                child: Text(locService.t('offlineAreas.renameButton')),
                              ),
                            ],
                          );
                        },
                      );
                      if (newName != null && newName.trim().isNotEmpty) {
                        setState(() {
                          area.name = newName.trim();
                          service.saveAreasToDisk();
                        });
                      }
                    },
                  ),
                if (area.status != OfflineAreaStatus.downloading) ...[
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.blue),
                    tooltip: locService.t('offlineAreas.refreshArea'),
                    onPressed: () => _showRefreshDialog(area),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: locService.t('offlineAreas.deleteOfflineArea'),
                    onPressed: () async {
                      service.deleteArea(area.id);
                      setState(() {});
                    },
                  ),
                ],
              ],
            ),
            subtitle: Text(subtitle),
            isThreeLine: true,
            trailing: area.status == OfflineAreaStatus.downloading
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 64,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            LinearProgressIndicator(value: area.progress),
                            Text(
                              locService.t('offlineAreas.progress', params: [(area.progress * 100).toStringAsFixed(0)]),
                              style: const TextStyle(fontSize: 12),
                            )
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.orange),
                        tooltip: locService.t('offlineAreas.cancelDownload'),
                        onPressed: () {
                          service.cancelDownload(area.id);
                          setState(() {});
                        },
                      )
                    ],
                  )
                : null,
            onLongPress: area.status == OfflineAreaStatus.downloading
                ? () {
                    service.cancelDownload(area.id);
                    setState(() {});
                  }
                : null,
          ),
          );
        }).toList(),
          ],
        );
      },
    );
  }
}

class _RefreshAreaDialog extends StatefulWidget {
  final OfflineArea area;
  final Function(bool refreshTiles, bool refreshNodes) onRefresh;

  const _RefreshAreaDialog({
    required this.area,
    required this.onRefresh,
  });

  @override
  State<_RefreshAreaDialog> createState() => _RefreshAreaDialogState();
}

class _RefreshAreaDialogState extends State<_RefreshAreaDialog> {
  bool _refreshTiles = true;
  bool _refreshNodes = true;

  @override
  Widget build(BuildContext context) {
    final locService = LocalizationService.instance;
    
    return AlertDialog(
      title: Text(locService.t('offlineAreas.refreshAreaDialogTitle')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(locService.t('offlineAreas.refreshAreaDialogSubtitle')),
          const SizedBox(height: 16),
          CheckboxListTile(
            title: Text(locService.t('offlineAreas.refreshTiles')),
            subtitle: Text(locService.t('offlineAreas.refreshTilesSubtitle')),
            value: _refreshTiles,
            onChanged: (value) => setState(() => _refreshTiles = value ?? true),
            dense: true,
          ),
          CheckboxListTile(
            title: Text(locService.t('offlineAreas.refreshNodes')),
            subtitle: Text(locService.t('offlineAreas.refreshNodesSubtitle')),
            value: _refreshNodes,
            onChanged: (value) => setState(() => _refreshNodes = value ?? true),
            dense: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(locService.t('actions.cancel')),
        ),
        ElevatedButton(
          onPressed: (_refreshTiles || _refreshNodes)
              ? () {
                  Navigator.of(context).pop();
                  widget.onRefresh(_refreshTiles, _refreshNodes);
                }
              : null,
          child: Text(locService.t('offlineAreas.startRefresh')),
        ),
      ],
    );
  }
}
