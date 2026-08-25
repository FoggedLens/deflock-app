import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../dev_config.dart';
import '../models/rf_detection.dart';

/// Bottom sheet displaying RF detection details with option to submit to OSM.
class RfDetectionSheet extends StatefulWidget {
  final RfDetection detection;

  const RfDetectionSheet({super.key, required this.detection});

  @override
  State<RfDetectionSheet> createState() => _RfDetectionSheetState();
}

class _RfDetectionSheetState extends State<RfDetectionSheet> {
  List<RfSighting>? _sightings;
  bool _loadingSightings = true;

  @override
  void initState() {
    super.initState();
    _loadSightings();
  }

  Future<void> _loadSightings() async {
    final appState = context.read<AppState>();
    final sightings =
        await appState.scannerState.getSightingsForMac(widget.detection.mac);
    if (mounted) {
      setState(() {
        _sightings = sightings;
        _loadingSightings = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final detection = widget.detection;
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: label + alert level badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    detection.label,
                    style: theme.textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _AlertLevelBadge(level: detection.alertLevel),
              ],
            ),

            const SizedBox(height: 4),

            // Category + radio type
            Text(
              '${detection.category} (${detection.radioType})',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),

            const SizedBox(height: 12),

            // Details in scrollable area
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height *
                    getTagListHeightRatio(context),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DetailRow(label: 'MAC', value: detection.mac),
                    _DetailRow(label: 'OUI', value: detection.oui),
                    if (detection.ssid != null)
                      _DetailRow(label: 'SSID', value: detection.ssid!),
                    if (detection.bleName != null)
                      _DetailRow(label: 'BLE Name', value: detection.bleName!),
                    _DetailRow(
                      label: 'Certainty',
                      value: '${detection.maxCertainty}%',
                    ),
                    _DetailRow(
                      label: 'Sightings',
                      value: detection.sightingCount.toString(),
                    ),
                    _DetailRow(
                      label: 'First Seen',
                      value: _formatDateTime(detection.firstSeenAt),
                    ),
                    _DetailRow(
                      label: 'Last Seen',
                      value: _formatDateTime(detection.lastSeenAt),
                    ),

                    // Detector matches
                    if (detection.detectorData.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Detector Matches',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...detection.detectorData.entries.map(
                        (e) => _DetailRow(
                          label: _formatDetectorName(e.key),
                          value: e.value.toString(),
                        ),
                      ),
                    ],

                    // Signal strength from sightings
                    if (!_loadingSightings && _sightings != null && _sightings!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Recent Signal Strength',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ..._sightings!.take(5).map(
                        (s) => _DetailRow(
                          label: _formatTime(s.seenAt),
                          value: '${s.rssi} dBm${s.channel != null ? ' (ch ${s.channel})' : ''}',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Coordinates
            if (detection.bestPosition != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DetailRow(
                  label: 'Position',
                  value:
                      '${detection.bestPosition!.latitude.toStringAsFixed(6)}, ${detection.bestPosition!.longitude.toStringAsFixed(6)}',
                ),
              ),

            // OSM link status
            if (detection.isSubmitted)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Submitted to DeFlock (node ${detection.osmNodeId})',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ),
                if (!detection.isSubmitted && appState.isLoggedIn)
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.upload, size: 18),
                      label: const Text('Submit to DeFlock'),
                      onPressed: () => _submitDetection(context, appState),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _submitDetection(BuildContext context, AppState appState) {
    // Start an add session with pre-filled data from the RF detection
    appState.startAddSession();

    // Find the best matching profile (Flock profile for flock detections)
    final profiles = appState.enabledProfiles;
    final flockProfile = profiles.where((p) => p.id == 'builtin-flock').firstOrNull;

    if (flockProfile != null && widget.detection.bestPosition != null) {
      appState.updateSession(
        profile: flockProfile,
        target: widget.detection.bestPosition,
      );
    }

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Adjust position and direction, then submit'),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  String _formatDetectorName(String name) {
    return name.replaceAll('_', ' ').split(' ').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1);
    }).join(' ');
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertLevelBadge extends StatelessWidget {
  final int level;

  const _AlertLevelBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    final String text;
    final Color color;

    switch (level) {
      case 3:
        text = 'CONFIRMED';
        color = Colors.red;
      case 2:
        text = 'SUSPICIOUS';
        color = Colors.orange;
      case 1:
        text = 'INFO';
        color = Colors.amber;
      default:
        text = 'UNKNOWN';
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
