// OpenStreetMap OAuth client IDs for this app.
// These must be provided via --dart-define at build time.
// In release (production) builds, missing keys throw so mis-configured
// builds fail fast. In debug builds (including tests) empty strings are
// returned so unit tests can run without --dart-define.

import 'package:flutter/foundation.dart';

String get kOsmProdClientId {
  const fromBuild = String.fromEnvironment('OSM_PROD_CLIENTID');
  if (fromBuild.isNotEmpty) return fromBuild;
  if (kReleaseMode) {
    throw Exception('OSM_PROD_CLIENTID not configured. Use --dart-define=OSM_PROD_CLIENTID=your_id');
  }
  return '';
}

String get kOsmSandboxClientId {
  const fromBuild = String.fromEnvironment('OSM_SANDBOX_CLIENTID');
  if (fromBuild.isNotEmpty) return fromBuild;
  if (kReleaseMode) {
    throw Exception('OSM_SANDBOX_CLIENTID not configured. Use --dart-define=OSM_SANDBOX_CLIENTID=your_id');
  }
  return '';
}
