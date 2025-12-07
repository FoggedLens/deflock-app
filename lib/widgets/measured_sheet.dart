import 'package:flutter/material.dart';

/// Wrapper widget that measures its child's height and reports changes via callback
class MeasuredSheet extends StatefulWidget {
  final Widget child;
  final ValueChanged<double> onHeightChanged;
  final String? debugLabel; // Add debug label for troubleshooting
  
  const MeasuredSheet({
    super.key,
    required this.child,
    required this.onHeightChanged,
    this.debugLabel,
  });

  @override
  State<MeasuredSheet> createState() => _MeasuredSheetState();
}

class _MeasuredSheetState extends State<MeasuredSheet> {
  final GlobalKey _key = GlobalKey();
  double _lastHeight = 0.0;

  @override
  void initState() {
    super.initState();
    // Schedule height measurement after first frame
    WidgetsBinding.instance.addPostFrameCallback(_measureHeight);
  }

  void _measureHeight(Duration _) {
    final renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final height = renderBox.size.height;
      if (height != _lastHeight) {
        _lastHeight = height;
        // Add debug logging to help troubleshoot height measurement issues
        if (widget.debugLabel != null) {
          debugPrint('[MeasuredSheet-${widget.debugLabel}] Height changed: $_lastHeight -> $height');
        }
        widget.onHeightChanged(height);
      }
    } else {
      // Add debug logging for measurement failures
      if (widget.debugLabel != null) {
        debugPrint('[MeasuredSheet-${widget.debugLabel}] Failed to measure height: renderBox is null');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (notification) {
        WidgetsBinding.instance.addPostFrameCallback(_measureHeight);
        return true;
      },
      child: SizeChangedLayoutNotifier(
        child: Container(
          key: _key,
          child: widget.child,
        ),
      ),
    );
  }
}