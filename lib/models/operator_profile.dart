import 'package:uuid/uuid.dart';
import 'osm_node.dart';

/// A bundle of OSM tags that describe a particular surveillance operator.
/// These are applied on top of camera profile tags during submissions.
class OperatorProfile {
  final String id;
  final String name;
  final Map<String, String> tags;

  OperatorProfile({
    required this.id,
    required this.name,
    required this.tags,
  });

  /// Get all built-in default operator profiles
  static List<OperatorProfile> getDefaults() => [
        OperatorProfile(
          id: 'builtin-lowes',
          name: "Lowe's",
          tags: const {
            'operator': "Lowe's",
            'operator:wikidata': 'Q1373493',
            'operator:type': 'private',
          },
        ),
        OperatorProfile(
          id: 'builtin-home-depot',
          name: 'The Home Depot',
          tags: const {
            'operator': 'The Home Depot',
            'operator:wikidata': 'Q864407',
            'operator:type': 'private',
          },
        ),
        OperatorProfile(
          id: 'builtin-simon-property-group',
          name: 'Simon Property Group',
          tags: const {
            'operator': 'Simon Property Group',
            'operator:wikidata': 'Q2287759',
            'operator:type': 'private',
          },
        ),
      ];

  OperatorProfile copyWith({
    String? id,
    String? name,
    Map<String, String>? tags,
  }) =>
      OperatorProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        tags: tags ?? this.tags,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tags': tags,
      };

  factory OperatorProfile.fromJson(Map<String, dynamic> j) => OperatorProfile(
        id: j['id'],
        name: j['name'],
        tags: Map<String, String>.from(j['tags']),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OperatorProfile &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  /// Create a temporary operator profile from existing operator tags on a node
  /// First tries to match against saved operator profiles, otherwise creates temporary one
  /// Used as the default operator profile when editing nodes
  static OperatorProfile? createExistingOperatorProfile(OsmNode node, List<OperatorProfile> savedProfiles) {
    final operatorTags = _extractOperatorTags(node.tags);
    if (operatorTags.isEmpty) return null;
    
    // First, try to find a perfect match among saved profiles
    for (final savedProfile in savedProfiles) {
      if (_tagsMatch(savedProfile.tags, operatorTags)) {
        return savedProfile;
      }
    }
    
    // No perfect match found, create temporary profile
    final operatorName = operatorTags['operator'] ?? '<existing>';
    
    return OperatorProfile(
      id: 'temp-existing-operator-${node.id}',
      name: operatorName,
      tags: operatorTags,
    );
  }

  /// Check if two tag maps are identical
  static bool _tagsMatch(Map<String, String> tags1, Map<String, String> tags2) {
    if (tags1.length != tags2.length) return false;
    
    for (final entry in tags1.entries) {
      if (tags2[entry.key] != entry.value) return false;
    }
    
    return true;
  }

  /// Extract all operator-related tags from a node's tags
  static Map<String, String> _extractOperatorTags(Map<String, String> tags) {
    final operatorTags = <String, String>{};
    
    for (final entry in tags.entries) {
      // Include operator= and any operator:*= tags
      if (entry.key == 'operator' || entry.key.startsWith('operator:')) {
        operatorTags[entry.key] = entry.value;
      }
    }
    
    return operatorTags;
  }

  /// Returns true if this is a temporary "existing operator" profile
  bool get isExistingOperatorProfile => id.startsWith('temp-existing-operator-');
}