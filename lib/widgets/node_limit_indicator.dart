import 'package:flutter/material.dart';
import '../services/localization_service.dart';

class NodeLimitIndicator extends StatelessWidget {
  final bool isActive;
  final int renderedCount;
  final int totalCount;
  
  const NodeLimitIndicator({
    super.key,
    required this.isActive,
    required this.renderedCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    if (!isActive) {
      return const SizedBox.shrink();
    }
    
    final locService = LocalizationService.instance;
    final message = locService.t('nodeLimitIndicator.message')
        .replaceAll('{rendered}', renderedCount.toString())
        .replaceAll('{total}', totalCount.toString());

    return Positioned(
      top: 8, // Position at top-left of map area
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.visibility_off,
              size: 16,
              color: Colors.amber,
            ),
            const SizedBox(width: 4),
            Text(
              message,
              style: const TextStyle(
                color: Colors.amber,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}