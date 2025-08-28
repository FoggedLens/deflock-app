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

  /// Built‑in default: Generic ALPR camera (view-only)
  factory CameraProfile.genericAlpr() => CameraProfile(
        id: 'builtin-generic-alpr',
        name: 'Generic ALPR',
        tags: const {
          'man_made': 'surveillance',
          'surveillance:type': 'ALPR',
        },
        builtin: true,
      );

  /// Built‑in: Flock Safety ALPR camera
  factory CameraProfile.flock() => CameraProfile(
        id: 'builtin-flock',
        name: 'Flock',
        tags: const {
          'man_made': 'surveillance',
          'surveillance': 'public',
          'surveillance:type': 'ALPR',
          'surveillance:zone': 'traffic',
          'camera:type': 'fixed',
          'manufacturer': 'Flock Safety',
          'manufacturer:wikidata': 'Q108485435',
        },
        builtin: true,
      );

  /// Built‑in: Motorola Solutions/Vigilant ALPR camera
  factory CameraProfile.motorola() => CameraProfile(
        id: 'builtin-motorola',
        name: 'Motorola/Vigilant',
        tags: const {
          'man_made': 'surveillance',
          'surveillance': 'public',
          'surveillance:type': 'ALPR',
          'surveillance:zone': 'traffic',
          'camera:type': 'fixed',
          'manufacturer': 'Motorola Solutions',
          'manufacturer:wikidata': 'Q634815',
        },
        builtin: true,
      );

  /// Built‑in: Genetec ALPR camera
  factory CameraProfile.genetec() => CameraProfile(
        id: 'builtin-genetec',
        name: 'Genetec',
        tags: const {
          'man_made': 'surveillance',
          'surveillance': 'public',
          'surveillance:type': 'ALPR',
          'surveillance:zone': 'traffic',
          'camera:type': 'fixed',
          'manufacturer': 'Genetec',
          'manufacturer:wikidata': 'Q30295174',
        },
        builtin: true,
      );

  /// Built‑in: Leonardo/ELSAG ALPR camera
  factory CameraProfile.leonardo() => CameraProfile(
        id: 'builtin-leonardo',
        name: 'Leonardo/ELSAG',
        tags: const {
          'man_made': 'surveillance',
          'surveillance': 'public',
          'surveillance:type': 'ALPR',
          'surveillance:zone': 'traffic',
          'camera:type': 'fixed',
          'manufacturer': 'Leonardo',
          'manufacturer:wikidata': 'Q910379',
        },
        builtin: true,
      );

  /// Built‑in: Neology ALPR camera
  factory CameraProfile.neology() => CameraProfile(
        id: 'builtin-neology',
        name: 'Neology',
        tags: const {
          'man_made': 'surveillance',
          'surveillance': 'public',
          'surveillance:type': 'ALPR',
          'surveillance:zone': 'traffic',
          'camera:type': 'fixed',
          'manufacturer': 'Neology, Inc.',
        },
        builtin: true,
      );

  /// Returns true if this profile can be used for submissions
  bool get isSubmittable {
    if (!builtin) return true; // All custom profiles are submittable
    // Only the generic ALPR builtin profile is not submittable
    return id != 'builtin-generic-alpr';
  }

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

