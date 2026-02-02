import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/rf_detection.dart';

/// Full-screen scanner management: live detection feed, stats, USB connection.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  int? _alertLevelFilter;
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final appState = context.read<AppState>();
    final stats = await appState.scannerState.getStats();
    if (mounted) {
      setState(() => _stats = stats);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final status = appState.scannerConnectionStatus;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RF Scanner'),
        actions: [
          // Connection status + reconnect
          IconButton(
            icon: Icon(
              appState.isScannerConnected ? Icons.usb : Icons.usb_off,
              color: appState.isScannerConnected ? Colors.green : null,
            ),
            tooltip: appState.isScannerConnected ? 'Connected' : 'Reconnect',
            onPressed: appState.isScannerConnected
                ? () => appState.disconnectScanner()
                : () => appState.reconnectScanner(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Status banner
          _ConnectionBanner(status: status, error: appState.scannerState.lastError),

          // Stats row
          if (_stats != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _StatChip(
                    label: 'Total',
                    value: '${_stats!['total']}',
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    label: 'Submitted',
                    value: '${_stats!['submitted']}',
                    color: Colors.green,
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    label: 'Pending',
                    value: '${_stats!['unsubmitted']}',
                    color: Colors.orange,
                  ),
                ],
              ),
            ),

          // Alert level filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('Filter: ', style: theme.textTheme.bodySmall),
                const SizedBox(width: 4),
                _FilterChip(
                  label: 'All',
                  selected: _alertLevelFilter == null,
                  onTap: () => setState(() => _alertLevelFilter = null),
                ),
                const SizedBox(width: 4),
                _FilterChip(
                  label: 'Confirmed',
                  selected: _alertLevelFilter == 3,
                  onTap: () => setState(() => _alertLevelFilter = 3),
                  color: Colors.red,
                ),
                const SizedBox(width: 4),
                _FilterChip(
                  label: 'Suspicious',
                  selected: _alertLevelFilter == 2,
                  onTap: () => setState(() => _alertLevelFilter = 2),
                  color: Colors.orange,
                ),
                const SizedBox(width: 4),
                _FilterChip(
                  label: 'Info',
                  selected: _alertLevelFilter == 1,
                  onTap: () => setState(() => _alertLevelFilter = 1),
                  color: Colors.amber,
                ),
              ],
            ),
          ),

          const Divider(),

          // Detection list
          Expanded(
            child: _DetectionList(
              scannerState: appState.scannerState,
              alertLevelFilter: _alertLevelFilter,
              onStatsChanged: _loadStats,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  final ScannerConnectionStatus status;
  final String? error;

  const _ConnectionBanner({required this.status, this.error});

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final String text;

    switch (status) {
      case ScannerConnectionStatus.connected:
        bgColor = Colors.green;
        text = 'Scanner connected — receiving detections';
      case ScannerConnectionStatus.connecting:
        bgColor = Colors.orange;
        text = 'Connecting to scanner...';
      case ScannerConnectionStatus.error:
        bgColor = Colors.red;
        text = error ?? 'Scanner error';
      case ScannerConnectionStatus.disconnected:
        bgColor = Colors.grey;
        text = 'Scanner disconnected — plug in M5StickC via USB';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: bgColor.withValues(alpha: 0.15),
      child: Row(
        children: [
          Icon(
            status == ScannerConnectionStatus.connected
                ? Icons.sensors
                : Icons.sensors_off,
            size: 16,
            color: bgColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: bgColor, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetectionList extends StatefulWidget {
  final ScannerState scannerState;
  final int? alertLevelFilter;
  final VoidCallback onStatsChanged;

  const _DetectionList({
    required this.scannerState,
    this.alertLevelFilter,
    required this.onStatsChanged,
  });

  @override
  State<_DetectionList> createState() => _DetectionListState();
}

class _DetectionListState extends State<_DetectionList> {
  List<RfDetection>? _detections;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // Reload when scanner state changes (new detections)
    widget.scannerState.addListener(_load);
  }

  @override
  void didUpdateWidget(_DetectionList old) {
    super.didUpdateWidget(old);
    if (old.alertLevelFilter != widget.alertLevelFilter) {
      _load();
    }
  }

  @override
  void dispose() {
    widget.scannerState.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final detections = await widget.scannerState.getDetections(
      minAlertLevel: widget.alertLevelFilter,
      limit: 200,
    );
    if (mounted) {
      setState(() {
        _detections = detections;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_detections == null || _detections!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sensors_off, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'No detections yet',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Text(
              'Connect M5StickC and drive near surveillance devices',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _load();
        widget.onStatsChanged();
      },
      child: ListView.separated(
        itemCount: _detections!.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final detection = _detections![index];
          return _DetectionTile(
            detection: detection,
            onDelete: () async {
              await widget.scannerState.deleteDetection(detection.mac);
              widget.onStatsChanged();
            },
          );
        },
      ),
    );
  }
}

class _DetectionTile extends StatelessWidget {
  final RfDetection detection;
  final VoidCallback onDelete;

  const _DetectionTile({required this.detection, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Color alertColor;
    switch (detection.alertLevel) {
      case 3:
        alertColor = Colors.red;
      case 2:
        alertColor = Colors.orange;
      case 1:
        alertColor = Colors.amber;
      default:
        alertColor = Colors.grey;
    }

    return Dismissible(
      key: ValueKey(detection.mac),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        leading: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: alertColor,
          ),
        ),
        title: Text(
          detection.label,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${detection.category} | ${detection.radioType} | ${detection.sightingCount} sighting${detection.sightingCount == 1 ? '' : 's'}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (detection.isSubmitted)
              const Icon(Icons.check_circle, color: Colors.green, size: 16),
            const SizedBox(width: 4),
            Text(
              '${detection.maxCertainty}%',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chipColor = color ?? theme.colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? chipColor.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? chipColor : theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? chipColor : theme.colorScheme.onSurface.withValues(alpha: 0.6),
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
