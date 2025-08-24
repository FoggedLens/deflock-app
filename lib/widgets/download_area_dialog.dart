import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;

import '../app_state.dart';
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
  int? _maxPossibleZoom;
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
    
    final minZoom = kWorldMaxZoom + 1;
    final maxZoom = _zoom.toInt();
    
    // Calculate maximum possible zoom based on tile count limit
    final maxPossibleZoom = _calculateMaxZoomForTileLimit(bounds, minZoom);
    
    final nTiles = computeTileList(bounds, minZoom, maxZoom).length;
    final totalMb = (nTiles * kTileEstimateKb) / 1024.0;
    
    setState(() {
      _minZoom = minZoom;
      _maxPossibleZoom = maxPossibleZoom;
      _tileCount = nTiles;
      _mbEstimate = totalMb;
    });
  }
  
  /// Calculate the maximum zoom level that keeps tile count under the limit
  int _calculateMaxZoomForTileLimit(LatLngBounds bounds, int minZoom) {
    for (int zoom = minZoom; zoom <= kAbsoluteMaxZoom; zoom++) {
      final tileCount = computeTileList(bounds, minZoom, zoom).length;
      if (tileCount > kMaxReasonableTileCount) {
        // Return the previous zoom level that was still under the limit
        return math.max(minZoom, zoom - 1);
      }
    }
    return kAbsoluteMaxZoom;
  }
  


  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final bounds = widget.controller.camera.visibleBounds;
    final maxZoom = _zoom.toInt();
    final isOfflineMode = appState.offlineMode;
    
    // Use the calculated max possible zoom instead of fixed span
    final sliderMin = _minZoom?.toDouble() ?? 12.0;
    final sliderMax = _maxPossibleZoom?.toDouble() ?? 19.0;
    final sliderDivisions = math.max(1, (_maxPossibleZoom ?? 19) - (_minZoom ?? 12));
    final sliderValue = _zoom.clamp(sliderMin, sliderMax);

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
              ),
            if (_maxPossibleZoom != null && _tileCount != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _tileCount! > kMaxReasonableTileCount 
                        ? Colors.orange.withOpacity(0.1)
                        : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Max recommended zoom: Z$_maxPossibleZoom',
                        style: TextStyle(
                          fontSize: 12,
                          color: _tileCount! > kMaxReasonableTileCount 
                              ? Colors.orange[700] 
                              : Colors.green[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _tileCount! > kMaxReasonableTileCount
                            ? 'Current selection exceeds ${kMaxReasonableTileCount.toString()} tile limit'
                            : 'Within ${kMaxReasonableTileCount.toString()} tile limit',
                        style: TextStyle(
                          fontSize: 11,
                          color: _tileCount! > kMaxReasonableTileCount 
                              ? Colors.orange[600] 
                              : Colors.green[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (isOfflineMode)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off, color: Colors.orange[700], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Downloads disabled while in offline mode. Disable offline mode to download new areas.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: isOfflineMode ? null : () async {
            try {
              final id = DateTime.now().toIso8601String().replaceAll(':', '-');
              final appDocDir = await OfflineAreaService().getOfflineAreaDir();
              final dir = "${appDocDir.path}/$id";
              
              // Get current tile provider info
              final appState = context.read<AppState>();
              final selectedProvider = appState.selectedTileProvider;
              final selectedTileType = appState.selectedTileType;
              
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
                tileProviderId: selectedProvider?.id,
                tileProviderName: selectedProvider?.name,
                tileTypeId: selectedTileType?.id,
                tileTypeName: selectedTileType?.name,
              );
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Download started! Fetching tiles and cameras...'),
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