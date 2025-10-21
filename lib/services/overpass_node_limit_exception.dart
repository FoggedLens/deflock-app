/// Exception thrown when Overpass API returns an error indicating too many nodes were requested.
/// This typically happens when querying large areas that would return more than 50k nodes.
class OverpassNodeLimitException implements Exception {
  final String message;
  final String? serverResponse;

  OverpassNodeLimitException(this.message, {this.serverResponse});

  @override
  String toString() => 'OverpassNodeLimitException: $message';
}