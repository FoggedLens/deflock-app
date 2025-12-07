import 'package:flutter/material.dart';

/// A wrapper that shifts a map's visual positioning to account for bottom sheets.
/// 
/// When a sheet is open, moves the map upward by the sheet height while extending
/// the map rendering area to fill the screen. This keeps the bottom edge visible
/// while shifting the visual center up so pins appear above the sheet.
class SheetAwareMap extends StatelessWidget {
  const SheetAwareMap({
    super.key,
    required this.child,
    this.sheetHeight = 0.0,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  /// The map widget to position
  final Widget child;
  
  /// Current height of the bottom sheet
  final double sheetHeight;
  
  /// Duration for smooth transitions when sheet height changes
  final Duration animationDuration;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use the actual available height from constraints, not full screen height
        final availableHeight = constraints.maxHeight;
        

        
        return Stack(
          children: [
            AnimatedPositioned(
              duration: animationDuration,
              curve: Curves.easeOut,
              // Move the map up by the sheet height
              top: -sheetHeight,
              left: 0,
              right: 0,
              // Extend the height to compensate and fill available area
              height: availableHeight + sheetHeight,
              child: child,
            ),
          ],
        );
      },
    );
  }
}