import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import '../../models/osm_camera_node.dart';

/// Status of an offline area
enum OfflineAreaStatus { downloading, complete, error, cancelled }

/// Model class describing an offline area for map/camera caching
class OfflineArea {
  final String id;
  String name;
  final LatLngBounds bounds;
  final int minZoom;
  final int maxZoom;
  final String directory; // base dir for area storage
  OfflineAreaStatus status;
  double progress; // 0.0 - 1.0
  int tilesDownloaded;
  int tilesTotal;
  List<OsmCameraNode> nodes;
  int sizeBytes; // Disk size in bytes
  final bool isPermanent; // Not user-deletable if true
  
  // Tile provider metadata (null for legacy areas)
  final String? tileProviderId;
  final String? tileProviderName;
  final String? tileTypeId;
  final String? tileTypeName;

  OfflineArea({
    required this.id,
    this.name = '',
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
    required this.directory,
    this.status = OfflineAreaStatus.downloading,
    this.progress = 0,
    this.tilesDownloaded = 0,
    this.tilesTotal = 0,
    this.nodes = const [],
    this.sizeBytes = 0,
    this.isPermanent = false,
    this.tileProviderId,
    this.tileProviderName,
    this.tileTypeId,
    this.tileTypeName,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'bounds': {
      'sw': {'lat': bounds.southWest.latitude, 'lng': bounds.southWest.longitude},
      'ne': {'lat': bounds.northEast.latitude, 'lng': bounds.northEast.longitude},
    },
    'minZoom': minZoom,
    'maxZoom': maxZoom,
    'directory': directory,
    'status': status.name,
    'progress': progress,
    'tilesDownloaded': tilesDownloaded,
    'tilesTotal': tilesTotal,
    'nodes': nodes.map((n) => n.toJson()).toList(),
    'sizeBytes': sizeBytes,
    'isPermanent': isPermanent,
    'tileProviderId': tileProviderId,
    'tileProviderName': tileProviderName,
    'tileTypeId': tileTypeId,
    'tileTypeName': tileTypeName,
  };

  static OfflineArea fromJson(Map<String, dynamic> json) {
    final bounds = LatLngBounds(
      LatLng(json['bounds']['sw']['lat'], json['bounds']['sw']['lng']),
      LatLng(json['bounds']['ne']['lat'], json['bounds']['ne']['lng']),
    );
    return OfflineArea(
      id: json['id'],
      name: json['name'] ?? '',
      bounds: bounds,
      minZoom: json['minZoom'],
      maxZoom: json['maxZoom'],
      directory: json['directory'],
      status: OfflineAreaStatus.values.firstWhere(
        (e) => e.name == json['status'], orElse: () => OfflineAreaStatus.error),
      progress: (json['progress'] ?? 0).toDouble(),
      tilesDownloaded: json['tilesDownloaded'] ?? 0,
      tilesTotal: json['tilesTotal'] ?? 0,
      nodes: (json['nodes'] as List? ?? json['cameras'] as List? ?? [])
          .map((e) => OsmCameraNode.fromJson(e)).toList(),
      sizeBytes: json['sizeBytes'] ?? 0,
      isPermanent: json['isPermanent'] ?? false,
      tileProviderId: json['tileProviderId'],
      tileProviderName: json['tileProviderName'],
      tileTypeId: json['tileTypeId'],
      tileTypeName: json['tileTypeName'],
    );
  }

  /// Get display text for the tile provider used in this area
  String get tileProviderDisplay {
    if (tileProviderName != null && tileTypeName != null) {
      return '$tileProviderName - $tileTypeName';
    } else if (tileTypeName != null) {
      return tileTypeName!;
    } else if (tileProviderName != null) {
      return tileProviderName!;
    } else {
      // Legacy area - assume OSM
      return 'OpenStreetMap (Legacy)';
    }
  }

  /// Check if this area has tile provider metadata
  bool get hasTileProviderInfo => tileProviderId != null && tileTypeId != null;
}
