import 'package:flutter/material.dart';

enum PinType {
  provisional, // Orange - current selection
  start,       // Green - route start
  end,         // Red - route end
}

/// A thumbtack-style pin for marking locations during search/routing
class LocationPin extends StatelessWidget {
  final PinType type;
  final double size;
  
  const LocationPin({
    super.key,
    required this.type,
    this.size = 32.0, // Smaller than before
  });

  Color get _pinColor {
    switch (type) {
      case PinType.provisional:
        return Colors.orange;
      case PinType.start:
        return Colors.green;
      case PinType.end:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pin shadow
          Positioned(
            bottom: 2,
            child: Container(
              width: size * 0.4,
              height: size * 0.2,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(size * 0.1),
              ),
            ),
          ),
          // Main thumbtack pin
          Icon(
            Icons.push_pin,
            size: size,
            color: _pinColor,
          ),
          // Inner dot for better visibility
          Positioned(
            top: size * 0.2,
            child: Container(
              width: size * 0.3,
              height: size * 0.3,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _pinColor.withValues(alpha: 0.8),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Legacy widget name for compatibility
class ProvisionalPin extends StatelessWidget {
  final double size;
  final Color color;
  
  const ProvisionalPin({
    super.key,
    this.size = 32.0,
    this.color = Colors.orange,
  });
  
  @override
  Widget build(BuildContext context) {
    return LocationPin(type: PinType.provisional, size: size);
  }
}