import 'package:flutter/material.dart';

/// A pin icon for marking provisional locations during search/routing
class ProvisionalPin extends StatelessWidget {
  final double size;
  final Color color;
  
  const ProvisionalPin({
    super.key,
    this.size = 48.0,
    this.color = Colors.red,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pin shadow
          Positioned(
            bottom: 0,
            child: Container(
              width: size * 0.3,
              height: size * 0.15,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(size * 0.15),
              ),
            ),
          ),
          // Main pin
          Icon(
            Icons.location_pin,
            size: size,
            color: color,
          ),
          // Inner dot
          Positioned(
            top: size * 0.15,
            child: Container(
              width: size * 0.25,
              height: size * 0.25,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withOpacity(0.8),
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}