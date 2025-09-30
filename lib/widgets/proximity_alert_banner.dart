import 'package:flutter/material.dart';

/// Simple red banner that flashes briefly when proximity alert is triggered
/// Follows brutalist principles: simple, explicit functionality
class ProximityAlertBanner extends StatefulWidget {
  final bool isVisible;
  final VoidCallback? onDismiss;
  
  const ProximityAlertBanner({
    super.key,
    required this.isVisible,
    this.onDismiss,
  });

  @override
  State<ProximityAlertBanner> createState() => _ProximityAlertBannerState();
}

class _ProximityAlertBannerState extends State<ProximityAlertBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
  }

  @override
  void didUpdateWidget(ProximityAlertBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        _controller.forward();
        // Auto-hide after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            _controller.reverse().then((_) {
              widget.onDismiss?.call();
            });
          }
        });
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        if (_animation.value == 0.0) {
          return const SizedBox.shrink();
        }
        
        return Positioned(
          top: MediaQuery.of(context).padding.top,
          left: 0,
          right: 0,
          child: Transform.translate(
            offset: Offset(0, -60 * (1 - _animation.value)),
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    _controller.reverse().then((_) {
                      widget.onDismiss?.call();
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Surveillance device nearby',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}