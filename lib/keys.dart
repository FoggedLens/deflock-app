// OpenStreetMap OAuth client IDs for this app.
// These must be provided via --dart-define at build time.

/// Whether OSM OAuth secrets were provided at build time.
/// When false, the app should force simulate mode.
bool get kHasOsmSecrets {
  const prod = String.fromEnvironment('OSM_PROD_CLIENTID');
  const sandbox = String.fromEnvironment('OSM_SANDBOX_CLIENTID');
  return prod.isNotEmpty && sandbox.isNotEmpty;
}

String get kOsmProdClientId {
  const fromBuild = String.fromEnvironment('OSM_PROD_CLIENTID');
  return fromBuild;
}

String get kOsmSandboxClientId {
  const fromBuild = String.fromEnvironment('OSM_SANDBOX_CLIENTID');
  return fromBuild;
}