import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/network_status.dart';
import '../services/localization_service.dart';

class NetworkStatusIndicator extends StatelessWidget {
  final double top;
  final double left;
  
  const NetworkStatusIndicator({
    super.key,
    this.top = 56.0,
    this.left = 8.0,
  });

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

            switch (networkStatus.currentStatus) {
              case NetworkStatusType.waiting:
                message = locService.t('networkStatus.loading');
                icon = Icons.hourglass_empty;
                color = Colors.blue;
                break;
                
              case NetworkStatusType.timedOut:
                message = locService.t('networkStatus.timedOut');
                icon = Icons.hourglass_disabled;
                color = Colors.orange;
                break;
                
              case NetworkStatusType.noData:
                message = locService.t('networkStatus.noData');
                icon = Icons.cloud_off;
                color = Colors.grey;
                break;

              case NetworkStatusType.success:
                message = locService.t('networkStatus.success');
                icon = Icons.check_circle;
                color = Colors.green;
                break;
                
              case NetworkStatusType.issues:
                switch (networkStatus.currentIssueType) {
                  case NetworkIssueType.overpassApi:
                    message = locService.t('networkStatus.nodeDataSlow');
                    icon = Icons.camera_alt_outlined;
                    color = Colors.orange;
                    break;
                  default:
                    return const SizedBox.shrink();
                }
                break;
                
              case NetworkStatusType.ready:
                return const SizedBox.shrink();
            }

            return Positioned(
              top: top, // Position dynamically based on other indicators
              left: left,
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
                    Icon(
                      icon,
                      size: 16,
                      color: color,
                    ),
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