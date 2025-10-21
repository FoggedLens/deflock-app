/// Exception thrown when Overpass API returns an error indicating too many nodes were requested.
/// This typically happens when querying large areas that would return more than 50k nodes.
class OverpassNodeLimitException implements Exception {
  final String message;
  final String? serverResponse;

  OverpassNodeLimitException(this.message, {this.serverResponse});

  @override
  String toString() => 'OverpassNodeLimitException: $message';
}

/// Exception thrown when Overpass API rate limits the request.
/// Should trigger longer backoff delays, not area splitting.
class OverpassRateLimitException implements Exception {
  final String message;
  final String? serverResponse;

  OverpassRateLimitException(this.message, {this.serverResponse});

  @override
  String toString() => 'OverpassRateLimitException: $message';
}