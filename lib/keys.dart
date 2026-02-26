// OpenStreetMap OAuth client IDs for this app.
// These must be provided via --dart-define at build time.

String get kOsmProdClientId {
  const fromBuild = String.fromEnvironment('OSM_PROD_CLIENTID');
  if (fromBuild.isNotEmpty) return fromBuild;

  throw Exception('OSM_PROD_CLIENTID not configured. Use --dart-define=OSM_PROD_CLIENTID=your_id');
}

String get kOsmSandboxClientId {
  const fromBuild = String.fromEnvironment('OSM_SANDBOX_CLIENTID');
  if (fromBuild.isNotEmpty) return fromBuild;

  throw Exception('OSM_SANDBOX_CLIENTID not configured. Use --dart-define=OSM_SANDBOX_CLIENTID=your_id');
}
