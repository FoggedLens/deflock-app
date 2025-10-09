// OpenStreetMap OAuth client IDs for this app.

import 'dart:io';

String _readFromProperties(String key) {
  final file = File('lib/keys.properties');
  if (!file.existsSync()) return '';
  
  final lines = file.readAsLinesSync();
  for (final line in lines) {
    if (line.startsWith(key + '=')) {
      return line.substring(key.length + 1);
    }
  }
  return '';
}

String get kOsmProdClientId {
  const fromBuild = String.fromEnvironment('OSM_PROD_CLIENTID');
  if (fromBuild.isNotEmpty) return fromBuild;
  
  final fromFile = _readFromProperties('OSM_PROD_CLIENTID');
  if (fromFile.isNotEmpty) return fromFile;
  
  throw Exception('OSM_PROD_CLIENTID not configured');
}

String get kOsmSandboxClientId {
  const fromBuild = String.fromEnvironment('OSM_SANDBOX_CLIENTID');
  if (fromBuild.isNotEmpty) return fromBuild;
  
  final fromFile = _readFromProperties('OSM_SANDBOX_CLIENTID');
  if (fromFile.isNotEmpty) return fromFile;
  
  throw Exception('OSM_SANDBOX_CLIENTID not configured');
}