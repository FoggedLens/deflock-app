/// A bundle of preset OSM tags that describe a particular camera model/type.
class CameraProfile {
  final String name;
  final Map<String, String> tags;

  const CameraProfile({
    required this.name,
    required this.tags,
  });

  // Built‑in ALPR profile (Flock Falcon‑style).
  factory CameraProfile.alpr() => const CameraProfile(
        name: 'ALPR Camera',
        tags: {
          'man_made': 'surveillance',
          'surveillance:type': 'ALPR',
          'surveillance': 'public',
          'surveillance:zone': 'traffic',
          'camera:type': 'fixed',
          'camera:mount': 'pole',
        },
      );

  CameraProfile copyWith({
    String? name,
    Map<String, String>? tags,
  }) =>
      CameraProfile(
        name: name ?? this.name,
        tags: tags ?? this.tags,
      );
}

