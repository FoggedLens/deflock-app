import 'package:http/http.dart' as http;

import '../dev_config.dart';
import 'version_service.dart';

/// An [http.BaseClient] that injects a User-Agent header into every request.
///
/// Reads the app name and version dynamically from [VersionService] so the UA
/// string stays in sync with pubspec.yaml without hard-coding values.
///
/// Uses [putIfAbsent] so a manually-set User-Agent is never overwritten.
class UserAgentClient extends http.BaseClient {
  final http.Client _inner;

  UserAgentClient([http.Client? inner]) : _inner = inner ?? http.Client();

  /// The User-Agent string sent with every request.
  ///
  /// Format follows OSM tile usage policy recommendations:
  /// `AppName/version (+homepage; contact: email)`
  static String get userAgent {
    final vs = VersionService();
    return '${vs.appName}/${vs.version} (+$kHomepageUrl; contact: $kContactEmail)';
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => userAgent);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
