/// Shared interface for entries managed by a [ServiceRegistry].
///
/// Both [ServiceEndpoint] and (in a future PR) [TileType] implement this,
/// enabling generic list management, persistence, and UI components.
abstract interface class ServiceRegistryEntry {
  /// Unique identifier for this entry.
  String get id;

  /// Human-readable display name.
  String get name;

  /// Whether this entry is active. Disabled entries are skipped by
  /// the resilience engine and hidden from primary selection UI.
  bool get enabled;

  /// Whether this entry was provided by the app (built-in default).
  /// Built-in entries cannot be deleted in production builds.
  bool get isBuiltIn;

  /// Serialize to JSON for SharedPreferences persistence.
  Map<String, dynamic> toJson();
}
