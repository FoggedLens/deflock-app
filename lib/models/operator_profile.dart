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