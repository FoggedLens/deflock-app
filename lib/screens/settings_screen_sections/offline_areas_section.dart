import 'package:flutter/material.dart';
import '../../services/offline_area_service.dart';

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

  @override
  Widget build(BuildContext context) {
    final areas = service.offlineAreas;
    if (areas.isEmpty) {
      return const ListTile(
        leading: Icon(Icons.download_for_offline),
        title: Text('No offline areas'),
        subtitle: Text('Download a map area for offline use.'),
      );
    }
    return Column(
      children: areas.map((area) {
        String diskStr = area.sizeBytes > 0
            ? area.sizeBytes > 1024 * 1024
                ? "${(area.sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB"
                : "${(area.sizeBytes / 1024).toStringAsFixed(1)} KB"
            : '--';
        String subtitle =
            'Z${area.minZoom}-${area.maxZoom}\n' +
                'Lat: ${area.bounds.southWest.latitude.toStringAsFixed(3)}, ${area.bounds.southWest.longitude.toStringAsFixed(3)}\n' +
                'Lat: ${area.bounds.northEast.latitude.toStringAsFixed(3)}, ${area.bounds.northEast.longitude.toStringAsFixed(3)}';
        if (area.status == OfflineAreaStatus.downloading) {
          subtitle += '\nTiles: ${area.tilesDownloaded} / ${area.tilesTotal}';
        } else {
          subtitle += '\nTiles: ${area.tilesTotal}';
        }
        subtitle += '\nSize: $diskStr';
        if (!area.isPermanent) {
          subtitle += '\nCameras: ${area.cameras.length}';
        }
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
                      : 'Area ${area.id.substring(0, 6)}...'),
                ),
                if (!area.isPermanent)
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    tooltip: 'Rename area',
                    onPressed: () async {
                      String? newName = await showDialog<String>(
                        context: context,
                        builder: (ctx) {
                          final ctrl = TextEditingController(text: area.name);
                          return AlertDialog(
                            title: const Text('Rename Offline Area'),
                            content: TextField(
                              controller: ctrl,
                              maxLength: 40,
                              decoration: const InputDecoration(labelText: 'Area Name'),
                              autofocus: true,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(ctx, ctrl.text.trim());
                                },
                                child: const Text('Rename'),
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
                if (area.isPermanent && area.status != OfflineAreaStatus.downloading)
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.blue),
                    tooltip: 'Refresh/re-download world tiles',
                    onPressed: () async {
                      await service.downloadArea(
                        id: area.id,
                        bounds: area.bounds,
                        minZoom: area.minZoom,
                        maxZoom: area.maxZoom,
                        directory: area.directory,
                        name: area.name,
                        onProgress: (progress) {},
                        onComplete: (status) {},
                      );
                      setState(() {});
                    },
                  )
                else if (!area.isPermanent && area.status != OfflineAreaStatus.downloading)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: 'Delete offline area',
                    onPressed: () async {
                      service.deleteArea(area.id);
                      setState(() {});
                    },
                  ),
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
                              '${(area.progress * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(fontSize: 12),
                            )
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.orange),
                        tooltip: 'Cancel download',
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
    );
  }
}
