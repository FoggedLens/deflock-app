import 'service_registry_entry.dart';

/// A configurable API endpoint with optional resilience overrides.
///
/// Used by [RoutingService] and [OverpassService] as entries in
/// their priority-ordered endpoint lists.
class ServiceEndpoint implements ServiceRegistryEntry {
  @override
  final String id;
  @override
  final String name;

  /// The endpoint URL (must be HTTPS).
  final String url;

  @override
  final bool enabled;
  @override
  final bool isBuiltIn;

  /// Override the service's default max retry count. Null = use default.
  final int? maxRetries;

  /// Override the service's default HTTP timeout in seconds. Null = use default.
  final int? timeoutSeconds;

  const ServiceEndpoint({
    required this.id,
    required this.name,
    required this.url,
    this.enabled = true,
    this.isBuiltIn = false,
    this.maxRetries,
    this.timeoutSeconds,
  });

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'enabled': enabled,
    'isBuiltIn': isBuiltIn,
    if (maxRetries != null) 'maxRetries': maxRetries,
    if (timeoutSeconds != null) 'timeoutSeconds': timeoutSeconds,
  };

  static ServiceEndpoint fromJson(Map<String, dynamic> json) => ServiceEndpoint(
    id: json['id'] as String,
    name: json['name'] as String,
    url: json['url'] as String,
    enabled: json['enabled'] as bool? ?? true,
    isBuiltIn: json['isBuiltIn'] as bool? ?? false,
    maxRetries: json['maxRetries'] as int?,
    timeoutSeconds: json['timeoutSeconds'] as int?,
  );

  ServiceEndpoint copyWith({
    String? id,
    String? name,
    String? url,
    bool? enabled,
    bool? isBuiltIn,
    int? maxRetries,
    int? timeoutSeconds,
  }) => ServiceEndpoint(
    id: id ?? this.id,
    name: name ?? this.name,
    url: url ?? this.url,
    enabled: enabled ?? this.enabled,
    isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    maxRetries: maxRetries ?? this.maxRetries,
    timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServiceEndpoint && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Default routing endpoints.
class DefaultServiceEndpoints {
  static List<ServiceEndpoint> routing() => const [
    ServiceEndpoint(
      id: 'routing-deflock',
      name: 'Deflock Primary',
      url: 'https://api.dontgetflocked.com/api/v1/deflock/directions',
      isBuiltIn: true,
    ),
    ServiceEndpoint(
      id: 'routing-alprwatch',
      name: 'ALPRWatch Fallback',
      url: 'https://alprwatch.org/api/v1/deflock/directions',
      isBuiltIn: true,
    ),
  ];

  static List<ServiceEndpoint> overpass() => const [
    ServiceEndpoint(
      id: 'overpass-deflock',
      name: 'Deflock Node Source',
      url: 'https://overpass.deflock.org/api/interpreter',
      isBuiltIn: true,
    ),
    ServiceEndpoint(
      id: 'overpass-public',
      name: 'Public Overpass',
      url: 'https://overpass-api.de/api/interpreter',
      isBuiltIn: true,
    ),
  ];
}
