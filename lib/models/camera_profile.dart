import 'package:uuid/uuid.dart';

/// A bundle of preset OSM tags that describe a particular camera model/type.
class CameraProfile {
  final String id;
  final String name;
  final Map<String, String> tags;
  final bool builtin;

  CameraProfile({
    required this.id,
    required this.name,
    required this.tags,
    this.builtin = false,
  });

  /// Built‑in default: Generic Flock ALPR camera
  factory CameraProfile.alpr() => CameraProfile(
        id: 'builtin-alpr',
        name: 'Generic Flock',
        tags: const {
          'man_made': 'surveillance',
          'surveillance': 'public',
          'surveillance:zone': 'traffic',
          'surveillance:type': 'ALPR', // left for backward compatibility — you may want to revisit per OSM best practice
          'camera:type': 'fixed',
          'manufacturer': 'Flock Safety',
          'manufacturer:wikidata': 'Q108485435',
        },
        builtin: true,
      );

  CameraProfile copyWith({
    String? id,
    String? name,
    Map<String, String>? tags,
    bool? builtin,
  }) =>
      CameraProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        tags: tags ?? this.tags,
        builtin: builtin ?? this.builtin,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'tags': tags, 'builtin': builtin};

  factory CameraProfile.fromJson(Map<String, dynamic> j) => CameraProfile(
        id: j['id'],
        name: j['name'],
        tags: Map<String, String>.from(j['tags']),
        builtin: j['builtin'] ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraProfile &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

