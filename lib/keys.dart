// OpenStreetMap OAuth client IDs for this app.
// These must be provided via --dart-define at build time.
// When not configured (e.g. in tests), empty strings are returned —
// OAuth login will fail at token request time, which is the expected
// behavior for test environments.

import 'package:flutter/foundation.dart';

String get kOsmProdClientId {
  const fromBuild = String.fromEnvironment('OSM_PROD_CLIENTID');
  if (fromBuild.isEmpty) {
    debugPrint('[keys] OSM_PROD_CLIENTID not configured — OAuth login will fail');
  }
  return fromBuild;
}

String get kOsmSandboxClientId {
  const fromBuild = String.fromEnvironment('OSM_SANDBOX_CLIENTID');
  if (fromBuild.isEmpty) {
    debugPrint('[keys] OSM_SANDBOX_CLIENTID not configured — OAuth login will fail');
  }
  return fromBuild;
}
