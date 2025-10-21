import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/network_status.dart';

class NetworkStatusIndicator extends StatelessWidget {
  const NetworkStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: NetworkStatus.instance,
      child: Consumer<NetworkStatus>(
        builder: (context, networkStatus, child) {
          String message;
          IconData icon;
          Color color;

          switch (networkStatus.currentStatus) {
            case NetworkStatusType.waiting:
              message = 'Loading...';
              icon = Icons.hourglass_empty;
              color = Colors.blue;
              break;
              
            case NetworkStatusType.timedOut:
              message = 'Timed out';
              icon = Icons.hourglass_disabled;
              color = Colors.orange;
              break;
              
            case NetworkStatusType.noData:
              message = 'No tiles here';
              icon = Icons.cloud_off;
              color = Colors.grey;
              break;

            case NetworkStatusType.success:
              message = 'Done';
              icon = Icons.check_circle;
              color = Colors.green;
              break;
              
            case NetworkStatusType.nodeLimitReached:
              message = 'Showing limit - increase in settings';
              icon = Icons.visibility_off;
              color = Colors.amber;
              break;
              
            case NetworkStatusType.issues:
              switch (networkStatus.currentIssueType) {
                case NetworkIssueType.osmTiles:
                  message = 'Tile provider slow';
                  icon = Icons.map_outlined;
                  color = Colors.orange;
                  break;
                case NetworkIssueType.overpassApi:
                  message = 'Camera data slow';
                  icon = Icons.camera_alt_outlined;
                  color = Colors.orange;
                  break;
                case NetworkIssueType.both:
                  message = 'Network issues';
                  icon = Icons.cloud_off_outlined;
                  color = Colors.red;
                  break;
                default:
                  return const SizedBox.shrink();
              }
              break;
              
            case NetworkStatusType.ready:
              return const SizedBox.shrink();
          }

          return Positioned(
            top: 8, // Position relative to the map area (not the screen)
            left: 8,
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
    );
  }
}