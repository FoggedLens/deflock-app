import 'package:latlong2/latlong.dart';
import 'direction_fov.dart';
import '../dev_config.dart';

class OsmNode {
  final int id;
  final LatLng coord;
  final Map<String, String> tags;
  final bool isConstrained; // true if part of any way/relation

  OsmNode({
    required this.id,
    required this.coord,
    required this.tags,
    this.isConstrained = false, // Default to unconstrained for backward compatibility
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'lat': coord.latitude,
    'lon': coord.longitude,
    'tags': tags,
    'isConstrained': isConstrained,
  };

  factory OsmNode.fromJson(Map<String, dynamic> json) {
    final tags = <String, String>{};
    if (json['tags'] != null) {
      (json['tags'] as Map<String, dynamic>).forEach((k, v) {
        tags[k.toString()] = v.toString();
      });
    }
    return OsmNode(
      id: json['id'] is int ? json['id'] as int : int.tryParse(json['id'].toString()) ?? 0,
      coord: LatLng((json['lat'] as num).toDouble(), (json['lon'] as num).toDouble()),
      tags: tags,
      isConstrained: json['isConstrained'] as bool? ?? false, // Default to false for backward compatibility
    );
  }

  bool get hasDirection => directionFovPairs.isNotEmpty;

  /// Get direction and FOV pairs, supporting range notation like "90-270" or "10-45;90-125;290"
  List<DirectionFov> get directionFovPairs {
    final raw = tags['direction'] ?? tags['camera:direction'];
    if (raw == null) return [];

    // Compass direction to degree mapping
    const compassDirections = {
      'N': 0.0, 'NNE': 22.5, 'NE': 45.0, 'ENE': 67.5,
      'E': 90.0, 'ESE': 112.5, 'SE': 135.0, 'SSE': 157.5,
      'S': 180.0, 'SSW': 202.5, 'SW': 225.0, 'WSW': 247.5,
      'W': 270.0, 'WNW': 292.5, 'NW': 315.0, 'NNW': 337.5,
    };

    final directionFovList = <DirectionFov>[];
    final parts = raw.split(';');
    
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      
      // Check if this part contains a range (e.g., "90-270")
      if (trimmed.contains('-') && RegExp(r'^\d+\.?\d*-\d+\.?\d*$').hasMatch(trimmed)) {
        final rangeParts = trimmed.split('-');
        if (rangeParts.length == 2) {
          final start = double.tryParse(rangeParts[0]);
          final end = double.tryParse(rangeParts[1]);
          
          if (start != null && end != null) {
            final normalized = _calculateRangeCenter(start, end);
            directionFovList.add(normalized);
            continue;
          }
        }
      }
      
      // Not a range, handle as single direction
      final trimmedUpper = trimmed.toUpperCase();
      
      // First try compass direction lookup
      if (compassDirections.containsKey(trimmedUpper)) {
        final degrees = compassDirections[trimmedUpper]!;
        directionFovList.add(DirectionFov(degrees, kDirectionConeHalfAngle * 2));
        continue;
      }
      
      // Then try numeric parsing
      final match = RegExp(r'[-+]?\d*\.?\d+').firstMatch(trimmed);
      if (match == null) continue;

      final numStr = match.group(0);
      final val = double.tryParse(numStr ?? '');
      if (val == null) continue;

      // Normalize: wrap negative or >360 into 0‑359 range
      final normalized = ((val % 360) + 360) % 360;
      directionFovList.add(DirectionFov(normalized, kDirectionConeHalfAngle * 2));
    }
    
    return directionFovList;
  }

  /// Calculate center and width for a range like "90-270" or "270-90"
  DirectionFov _calculateRangeCenter(double start, double end) {
    // Normalize start and end to 0-359 range
    start = ((start % 360) + 360) % 360;
    end = ((end % 360) + 360) % 360;
    
    double width, center;
    
    if (start > end) {
      // Wrapping case: 270-90
      width = (end + 360) - start;
      center = ((start + end + 360) / 2) % 360;
    } else {
      // Normal case: 90-270  
      width = end - start;
      center = (start + end) / 2;
    }
    
    return DirectionFov(center, width);
  }

  /// Legacy getter for backward compatibility - returns just center directions
  List<double> get directionDeg {
    return directionFovPairs.map((df) => df.centerDegrees).toList();
  }
}