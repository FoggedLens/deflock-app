import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;

import '../app_state.dart';
import '../dev_config.dart';
import '../services/localization_service.dart';
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
    
    final minZoom = 1; // Always start from zoom 1 to show area overview when zoomed out
    final maxZoom = _zoom.toInt();
    
    // Calculate maximum possible zoom based on tile count limit
    final maxPossibleZoom = _calculateMaxZoomForTileLimit(bounds, minZoom);
    
    final nTiles = computeTileList(bounds, minZoom, maxZoom).length;
    final totalMb = (nTiles * kTileEstimateKb) / 1024.0;
    final roundedMb = (totalMb * 10).round() / 10; // Round to nearest tenth
    
    setState(() {
      _minZoom = minZoom;
      _maxPossibleZoom = maxPossibleZoom;
      _tileCount = nTiles;
      _mbEstimate = roundedMb;
    });
  }
  
  /// Calculate the maximum zoom level that keeps tile count under the absolute limit
  int _calculateMaxZoomForTileLimit(LatLngBounds bounds, int minZoom) {
    for (int zoom = minZoom; zoom <= kAbsoluteMaxZoom; zoom++) {
      final tileCount = computeTileList(bounds, minZoom, zoom).length;
      if (tileCount > kAbsoluteMaxTileCount) {
        // Return the previous zoom level that was still under the absolute limit
        return math.max(minZoom, zoom - 1);
      }
    }
    return kAbsoluteMaxZoom;
  }
  


  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
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
            children: [
              const Icon(Icons.download_for_offline),
              const SizedBox(width: 10),
              Text(locService.t('download.title')),
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
                    Text(locService.t('download.maxZoomLevel')),
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
                    Text(locService.t('download.storageEstimate')),
                    Expanded(
                      child: Text(
                        _mbEstimate == null
                            ? '…'
                            : locService.t('download.tilesAndSize', params: [
                                _tileCount.toString(),
                                _mbEstimate!.toStringAsFixed(1)
                              ]),
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
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
                            _tileCount! > kMaxReasonableTileCount 
                                ? 'Above recommended limit (Z${_maxPossibleZoom})'
                                : locService.t('download.maxRecommendedZoom', params: [_maxPossibleZoom.toString()]),
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
                                ? 'Current selection exceeds ${kMaxReasonableTileCount} recommended tile limit but is within ${kAbsoluteMaxTileCount} absolute limit'
                                : locService.t('download.withinTileLimit', params: [kMaxReasonableTileCount.toString()]),
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
                              locService.t('download.offlineModeWarning'),
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
              child: Text(locService.cancel),
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
                    minZoom: _minZoom ?? 1,
                    maxZoom: _zoom.toInt(),
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
                    SnackBar(
                      content: Text(locService.t('download.downloadStarted')),
                    ),
                  );
                } catch (e) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(locService.t('download.downloadFailed', params: [e.toString()])),
                    ),
                  );
                }
              },
              child: Text(locService.download),
            ),
          ],
        );
      },
    );
  }
}