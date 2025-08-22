import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../dev_config.dart';
import '../services/offline_area_service.dart';
import '../services/offline_areas/offline_tile_utils.dart';

class DownloadAreaDialog extends StatefulWidget {
  final MapController controller;
  const DownloadAreaDialog({super.key, required this.controller});

  @override
  State<DownloadAreaDialog> createState() => _DownloadAreaDialogState();
}

class _DownloadAreaDialogState extends State<DownloadAreaDialog> {
  double _zoom = 15;
  int? _minZoom;
  int? _tileCount;
  double? _mbEstimate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeEstimates());
  }

  void _recomputeEstimates() {
    var bounds = widget.controller.camera.visibleBounds;
    // If the visible area is nearly zero, nudge the bounds for estimation
    const double epsilon = 0.0002;
    final latSpan = (bounds.north - bounds.south).abs();
    final lngSpan = (bounds.east - bounds.west).abs();
    if (latSpan < epsilon && lngSpan < epsilon) {
      bounds = LatLngBounds(
        LatLng(bounds.southWest.latitude - epsilon, bounds.southWest.longitude - epsilon),
        LatLng(bounds.northEast.latitude + epsilon, bounds.northEast.longitude + epsilon)
      );
    } else if (latSpan < epsilon) {
      bounds = LatLngBounds(
        LatLng(bounds.southWest.latitude - epsilon, bounds.southWest.longitude),
        LatLng(bounds.northEast.latitude + epsilon, bounds.northEast.longitude)
      );
    } else if (lngSpan < epsilon) {
      bounds = LatLngBounds(
        LatLng(bounds.southWest.latitude, bounds.southWest.longitude - epsilon),
        LatLng(bounds.northEast.latitude, bounds.northEast.longitude + epsilon)
      );
    }
    final minZoom = kWorldMaxZoom + 1; // Use world max zoom + 1 for seamless zoom experience
    final maxZoom = _zoom.toInt();
    final nTiles = computeTileList(bounds, minZoom, maxZoom).length;
    final totalMb = (nTiles * kTileEstimateKb) / 1024.0;
    setState(() {
      _minZoom = minZoom;
      _tileCount = nTiles;
      _mbEstimate = totalMb;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bounds = widget.controller.camera.visibleBounds;
    final maxZoom = _zoom.toInt();
    double sliderMin;
    double sliderMax;
    int sliderDivisions;
    double sliderValue;
    // Generate slider min/max/divisions with clarity
    if (_minZoom != null) {
      sliderMin = _minZoom!.toDouble();
    } else {
      sliderMin = 12.0; //fallback
    }
    if (_minZoom != null) {
      final candidateMax = _minZoom! + kMaxUserDownloadZoomSpan;
      sliderMax = candidateMax > 19 ? 19.0 : candidateMax.toDouble();
    } else {
      sliderMax = 19.0; //fallback
    }
    if (_minZoom != null) {
      final candidateMax = _minZoom! + kMaxUserDownloadZoomSpan;
      int diff = (candidateMax > 19 ? 19 : candidateMax) - _minZoom!;
      sliderDivisions = diff > 0 ? diff : 1;
    } else {
      sliderDivisions = 7; //fallback
    }
    sliderValue = _zoom.clamp(sliderMin, sliderMax);
    // We recompute estimates when the zoom slider changes

    return AlertDialog(
      title: Row(
        children: const [
          Icon(Icons.download_for_offline),
          SizedBox(width: 10),
          Text("Download Map Area"),
        ],
      ),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Max zoom level'),
                Text('Z${_zoom.toStringAsFixed(0)}'),
              ],
            ),

            Slider(
              min: sliderMin,
              max: sliderMax,
              divisions: sliderDivisions,
              label: 'Z${_zoom.toStringAsFixed(0)}',
              value: sliderValue,
              onChanged: (v) {
                setState(() => _zoom = v);
                WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeEstimates());
              },
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Storage estimate:'),
                Expanded(
                  child: Text(
                    _mbEstimate == null
                        ? '…'
                        : '${_tileCount} tiles, ${_mbEstimate!.toStringAsFixed(1)} MB',
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            if (_minZoom != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Min zoom:'),
                  Text('Z$_minZoom'),
                ],
              )
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            try {
              final id = DateTime.now().toIso8601String().replaceAll(':', '-');
              final appDocDir = await OfflineAreaService().getOfflineAreaDir();
              final dir = "${appDocDir.path}/$id";
              // Fire and forget: don't await download, so dialog closes immediately
              // ignore: unawaited_futures
              OfflineAreaService().downloadArea(
                id: id,
                bounds: bounds,
                minZoom: _minZoom ?? 12,
                maxZoom: maxZoom,
                directory: dir,
                onProgress: (progress) {},
                onComplete: (status) {},
              );
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Download started!'),
                ),
              );
            } catch (e) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to start download: $e'),
                ),
              );
            }
          },
          child: const Text('Download'),
        ),
      ],
    );
  }
}