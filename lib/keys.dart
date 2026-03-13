// Build-time API keys, provided via --dart-define.

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

// Stadia Maps API key (optional — vector tiles won't load without it).
const kStadiaApiKey = String.fromEnvironment('STADIA_API_KEY');
