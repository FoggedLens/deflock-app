import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/network_status.dart';
import '../services/localization_service.dart';

class NetworkStatusIndicator extends StatefulWidget {
  final double top;
  final double left;

  const NetworkStatusIndicator({
    super.key,
    this.top = 56.0,
    this.left = 8.0,
  });

  @override
  State<NetworkStatusIndicator> createState() => _NetworkStatusIndicatorState();
}

class _NetworkStatusIndicatorState extends State<NetworkStatusIndicator>
    with SingleTickerProviderStateMixin {
  AnimationController? _countdownController;
  int _countdownTotal = 0; // Original total from first rate limit in this cooldown

  void _onStatusChanged() {
    if (!mounted) return;
    final status = NetworkStatus.instance;
    if (status.status == NetworkRequestStatus.rateLimited &&
        status.rateLimitWaitSeconds > 0) {
      setState(() => _updateCountdown(status.rateLimitWaitSeconds));
    } else {
      setState(() {
        _countdownController?.dispose();
        _countdownController = null;
        _countdownTotal = 0;
      });
    }
  }

  void _updateCountdown(int waitSeconds) {
    if (_countdownController == null || !_countdownController!.isAnimating) {
      // First rate limit in this cooldown — start fresh
      _countdownTotal = waitSeconds;
      _countdownController?.dispose();
      _countdownController = AnimationController(
        vsync: this,
        duration: Duration(seconds: waitSeconds),
      )..forward();
    } else {
      // Update from server — jump forward to match, keep draining
      // e.g. started at 14s, server now says 8s → progress = 1 - 8/14 ≈ 0.43
      final progress = 1.0 - (waitSeconds / _countdownTotal).clamp(0.0, 1.0);
      _countdownController!.duration = Duration(seconds: _countdownTotal);
      _countdownController!.forward(from: progress);
    }
  }

  @override
  void initState() {
    super.initState();
    NetworkStatus.instance.addListener(_onStatusChanged);
    _onStatusChanged();
  }

  @override
  void dispose() {
    NetworkStatus.instance.removeListener(_onStatusChanged);
    _countdownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) => ChangeNotifierProvider.value(
        value: NetworkStatus.instance,
        child: Consumer<NetworkStatus>(
          builder: (context, networkStatus, child) {
            final locService = LocalizationService.instance;
            String message;
            IconData icon;
            Color color;

            switch (networkStatus.status) {
              case NetworkRequestStatus.loading:
                message = locService.t('networkStatus.loading');
                icon = Icons.hourglass_empty;
                color = Colors.blue;
                break;

              case NetworkRequestStatus.splitting:
                message = locService.t('networkStatus.nodeDataSlow');
                icon = Icons.camera_alt_outlined;
                color = Colors.orange;
                break;

              case NetworkRequestStatus.success:
                message = locService.t('networkStatus.success');
                icon = Icons.check_circle;
                color = Colors.green;
                break;

              case NetworkRequestStatus.timeout:
                message = locService.t('networkStatus.timedOut');
                icon = Icons.hourglass_disabled;
                color = Colors.orange;
                break;

              case NetworkRequestStatus.rateLimited:
                message = locService.t('networkStatus.rateLimited');
                icon = Icons.speed;
                color = Colors.red;
                break;

              case NetworkRequestStatus.noData:
                message = locService.t('networkStatus.noData');
                icon = Icons.cloud_off;
                color = Colors.grey;
                break;

              case NetworkRequestStatus.error:
                message = locService.t('networkStatus.networkError');
                icon = Icons.error_outline;
                color = Colors.red;
                break;

              case NetworkRequestStatus.idle:
                return const SizedBox.shrink();
            }

            // For rate limited: show countdown circle instead of static icon
            Widget iconWidget;
            if (networkStatus.status == NetworkRequestStatus.rateLimited &&
                _countdownController != null) {
              iconWidget = AnimatedBuilder(
                animation: _countdownController!,
                builder: (context, child) {
                  final remaining = _countdownTotal *
                      (1.0 - _countdownController!.value);
                  return SizedBox(
                    width: 18,
                    height: 18,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: 1.0 - _countdownController!.value,
                          strokeWidth: 2,
                          color: color,
                          backgroundColor: color.withValues(alpha: 0.2),
                        ),
                        Text(
                          '${remaining.ceil()}',
                          style: TextStyle(
                            color: color,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            } else {
              iconWidget = Icon(icon, size: 16, color: color);
            }

            return Positioned(
              top: widget.top,
              left: widget.left,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    iconWidget,
                    const SizedBox(width: 4),
                    Text(
                      message,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
