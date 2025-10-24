import 'package:uuid/uuid.dart';

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

  /// Built-in default: Lowe's operator profile
  factory OperatorProfile.lowes() => getDefaults()[0];

  /// Built-in default: The Home Depot operator profile  
  factory OperatorProfile.homeDepot() => getDefaults()[1];

  /// Built-in default: Simon Property Group operator profile
  factory OperatorProfile.simonPropertyGroup() => getDefaults()[2];

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
}