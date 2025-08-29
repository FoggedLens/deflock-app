import 'package:uuid/uuid.dart';

/// A bundle of preset OSM tags that describe a particular camera model/type.
class CameraProfile {
  final String id;
  final String name;
  final Map<String, String> tags;
  final bool builtin;
  final bool requiresDirection;
  final bool submittable;
  final bool editable;

  CameraProfile({
    required this.id,
    required this.name,
    required this.tags,
    this.builtin = false,
    this.requiresDirection = true,
    this.submittable = true,
    this.editable = true,
  });

  /// Built‑in default: Generic ALPR camera (customizable template, not submittable)
  factory CameraProfile.genericAlpr() => CameraProfile(
        id: 'builtin-generic-alpr',
        name: 'Generic ALPR',
        tags: const {
          'man_made': 'surveillance',
          'surveillance:type': 'ALPR',
        },
        builtin: true,
        requiresDirection: true,
        submittable: false,
        editable: false,
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
        requiresDirection: true,
        submittable: true,
        editable: false,
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
        requiresDirection: true,
        submittable: true,
        editable: false,
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
        requiresDirection: true,
        submittable: true,
        editable: false,
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
        requiresDirection: true,
        submittable: true,
        editable: false,
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
        requiresDirection: true,
        submittable: true,
        editable: false,
      );

  /// Built‑in: Generic gunshot detector (customizable template, not submittable)
  factory CameraProfile.genericGunshotDetector() => CameraProfile(
        id: 'builtin-generic-gunshot',
        name: 'Generic Gunshot Detector',
        tags: const {
          'man_made': 'surveillance',
          'surveillance:type': 'gunshot_detector',
        },
        builtin: true,
        requiresDirection: false,
        submittable: false,
        editable: false,
      );

  /// Built‑in: ShotSpotter gunshot detector
  factory CameraProfile.shotspotter() => CameraProfile(
        id: 'builtin-shotspotter',
        name: 'ShotSpotter',
        tags: const {
          'man_made': 'surveillance',
          'surveillance': 'public',
          'surveillance:type': 'gunshot_detector',
          'surveillance:brand': 'ShotSpotter',
          'surveillance:brand:wikidata': 'Q107740188',
        },
        builtin: true,
        requiresDirection: false,
        submittable: true,
        editable: false,
      );

  /// Built‑in: Flock Raven gunshot detector
  factory CameraProfile.flockRaven() => CameraProfile(
        id: 'builtin-flock-raven',
        name: 'Flock Raven',
        tags: const {
          'man_made': 'surveillance',
          'surveillance': 'public',
          'surveillance:type': 'gunshot_detector',
          'brand': 'Flock Safety',
          'brand:wikidata': 'Q108485435',
        },
        builtin: true,
        requiresDirection: false,
        submittable: true,
        editable: false,
      );

  /// Returns true if this profile can be used for submissions
  bool get isSubmittable => submittable;

  CameraProfile copyWith({
    String? id,
    String? name,
    Map<String, String>? tags,
    bool? builtin,
    bool? requiresDirection,
    bool? submittable,
    bool? editable,
  }) =>
      CameraProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        tags: tags ?? this.tags,
        builtin: builtin ?? this.builtin,
        requiresDirection: requiresDirection ?? this.requiresDirection,
        submittable: submittable ?? this.submittable,
        editable: editable ?? this.editable,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tags': tags,
        'builtin': builtin,
        'requiresDirection': requiresDirection,
        'submittable': submittable,
        'editable': editable,
      };

  factory CameraProfile.fromJson(Map<String, dynamic> j) => CameraProfile(
        id: j['id'],
        name: j['name'],
        tags: Map<String, String>.from(j['tags']),
        builtin: j['builtin'] ?? false,
        requiresDirection: j['requiresDirection'] ?? true, // Default to true for backward compatibility
        submittable: j['submittable'] ?? true, // Default to true for backward compatibility
        editable: j['editable'] ?? true, // Default to true for backward compatibility
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

