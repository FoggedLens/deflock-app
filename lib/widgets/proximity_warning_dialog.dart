import 'package:flutter/material.dart';

import '../models/osm_node.dart';
import '../services/localization_service.dart';

class ProximityWarningDialog extends StatelessWidget {
  final List<OsmNode> nearbyNodes;
  final double distance;
  final VoidCallback onGoBack;
  final VoidCallback onSubmitAnyway;

  const ProximityWarningDialog({
    super.key,
    required this.nearbyNodes,
    required this.distance,
    required this.onGoBack,
    required this.onSubmitAnyway,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        
        return AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange,
            size: 32,
          ),
          title: Text(locService.t('proximityWarning.title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                locService.t('proximityWarning.message', 
                  params: [distance.toStringAsFixed(1)]),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text(
                locService.t('proximityWarning.suggestion'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                locService.t('proximityWarning.nearbyNodes', 
                  params: [nearbyNodes.length.toString()]),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ...nearbyNodes.take(3).map((node) => Padding(
                padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                child: Text(
                  '• ${locService.t('proximityWarning.nodeInfo', params: [
                    node.id.toString(),
                    _getNodeTypeDescription(node, locService),
                  ])}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )),
              if (nearbyNodes.length > 3)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                  child: Text(
                    locService.t('proximityWarning.andMore', 
                      params: [(nearbyNodes.length - 3).toString()]),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: onGoBack,
              child: Text(locService.t('proximityWarning.goBack')),
            ),
            ElevatedButton(
              onPressed: onSubmitAnyway,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: Text(locService.t('proximityWarning.submitAnyway')),
            ),
          ],
        );
      },
    );
  }

  String _getNodeTypeDescription(OsmNode node, LocalizationService locService) {
    // Try to get a meaningful description from the node's tags
    final manMade = node.tags['man_made'];
    final amenity = node.tags['amenity'];
    final surveillance = node.tags['surveillance'];
    final surveillanceType = node.tags['surveillance:type'];
    final manufacturer = node.tags['manufacturer'];
    
    if (manMade == 'surveillance') {
      if (surveillanceType == 'ALPR' || surveillanceType == 'ANPR') {
        return locService.t('proximityWarning.nodeType.alpr');
      } else if (surveillance == 'public') {
        return locService.t('proximityWarning.nodeType.publicCamera');
      } else {
        return locService.t('proximityWarning.nodeType.camera');
      }
    } else if (amenity != null) {
      return locService.t('proximityWarning.nodeType.amenity', params: [amenity]);
    } else if (manufacturer != null) {
      return locService.t('proximityWarning.nodeType.device', params: [manufacturer]);
    } else {
      return locService.t('proximityWarning.nodeType.unknown');
    }
  }
}