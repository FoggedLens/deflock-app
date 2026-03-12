import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' hide TileLayer;

import '../models/tile_provider.dart' show kApiKeyPlaceholder;
import 'http_client.dart';

/// Singleton service that loads and caches vector tile styles.
///
/// Replaces [StyleReader] to properly propagate API keys to all sub-URLs
/// (source TileJSON endpoints, tile data URLs, sprite URLs, glyph URLs).
/// The upstream [StyleReader] only handles `{key}` token substitution for
/// non-Mapbox providers, which doesn't work for providers like Stadia Maps
/// that require query-parameter authentication on every request.
///
/// Features:
/// - In-memory cache keyed by `styleUrl|apiKey`
/// - Deduplication of concurrent loads (same key returns same Future)
/// - `{api_key}` substitution in all URLs derived from the style JSON
/// - [evict] and [clear] methods for cache management
class VectorStyleService {
  VectorStyleService._() : _httpClient = UserAgentClient();
  static final VectorStyleService instance = VectorStyleService._();

  /// Shared HTTP client with User-Agent header for all style/tile/sprite requests.
  final http.Client _httpClient;

  /// Cached styles keyed by `styleUrl|apiKey`.
  final Map<String, Style> _cache = {};

  /// In-flight load futures for deduplication.
  final Map<String, Future<Style>> _pending = {};

  /// Load a vector tile style, returning a cached result if available.
  ///
  /// [styleUrl] is the style JSON URL (may contain `{api_key}`).
  /// [apiKey] is substituted into the URL if present.
  Future<Style> load(String styleUrl, {String? apiKey}) {
    final cacheKey = _cacheKey(styleUrl, apiKey);

    // Return cached style if available
    final cached = _cache[cacheKey];
    if (cached != null) return Future.value(cached);

    // Deduplicate concurrent loads
    return _pending.putIfAbsent(cacheKey, () async {
      try {
        final style = await _loadStyle(styleUrl, apiKey);
        _cache[cacheKey] = style;
        debugPrint('[VectorStyleService] Style loaded and cached for: ${_safeUrl(styleUrl)}');
        return style;
      } finally {
        _pending.remove(cacheKey);
      }
    });
  }

  /// Evict a specific style from the cache.
  void evict(String styleUrl, {String? apiKey}) {
    final key = _cacheKey(styleUrl, apiKey);
    _cache.remove(key);
  }

  /// Clear all cached styles and cancel pending loads.
  void clear() {
    _cache.clear();
    _pending.clear();
  }

  /// Whether a style is already cached.
  bool isCached(String styleUrl, {String? apiKey}) {
    return _cache.containsKey(_cacheKey(styleUrl, apiKey));
  }

  /// Get a cached style without loading, or null if not cached.
  Style? getCached(String styleUrl, {String? apiKey}) {
    return _cache[_cacheKey(styleUrl, apiKey)];
  }

  String _cacheKey(String styleUrl, String? apiKey) =>
      '$styleUrl|${apiKey ?? ''}';

  /// Resolve `{api_key}` tokens in a URL.
  String _resolveUrl(String url, String? apiKey) {
    if (apiKey != null && apiKey.isNotEmpty) {
      return url.replaceAll(kApiKeyPlaceholder, apiKey);
    }
    return url;
  }

  /// Append or merge the API key into a URL as a query parameter.
  ///
  /// Uses the same parameter name found in the style URL (e.g. `api_key`
  /// for Stadia Maps, `key` for MapTiler). Falls back to `api_key`.
  String _appendApiKey(String url, String apiKey, String paramName) {
    final uri = Uri.parse(url);
    if (uri.queryParameters.containsKey(paramName)) {
      // Already has the key parameter
      return url;
    }
    final separator = uri.query.isEmpty ? '?' : '&';
    return '$url$separator$paramName=${Uri.encodeQueryComponent(apiKey)}';
  }

  /// Detect the API key query parameter name from a URL template.
  ///
  /// e.g. `?api_key={api_key}` → `api_key`, `?key={api_key}` → `key`
  String _detectKeyParamName(String urlTemplate) {
    final uri = Uri.parse(urlTemplate.replaceAll(kApiKeyPlaceholder, 'PLACEHOLDER'));
    for (final entry in uri.queryParameters.entries) {
      if (entry.value == 'PLACEHOLDER') return entry.key;
    }
    return 'api_key';
  }

  /// Strip query parameters from a URL for safe logging.
  String _safeUrl(String url) => url.split('?').first;

  /// Fetch, parse, and construct a [Style] with proper API key propagation.
  Future<Style> _loadStyle(String styleUrl, String? apiKey) async {
    final resolvedUrl = _resolveUrl(styleUrl, apiKey);
    final keyParam = _detectKeyParamName(styleUrl);
    debugPrint('[VectorStyleService] Loading style: ${_safeUrl(resolvedUrl)}');

    // 1. Fetch style JSON
    final styleText = await _httpGet(resolvedUrl);
    final styleJson =
        await compute(jsonDecode, styleText) as Map<String, dynamic>;

    // 2. Parse tile sources — fetch TileJSON with API key propagated
    final sources = styleJson['sources'];
    if (sources is! Map) {
      throw FormatException('Style JSON missing "sources": ${_safeUrl(resolvedUrl)}');
    }
    final providers = await _readProviders(
      sources: sources,
      apiKey: apiKey,
      keyParam: keyParam,
    );

    // 3. Parse theme
    final theme = ThemeReader(logger: const Logger.noop()).read(styleJson);

    // 4. Parse sprites (with API key propagated)
    final sprites = await _readSprites(
      styleJson: styleJson,
      apiKey: apiKey,
      keyParam: keyParam,
    );

    return Style(
      name: styleJson['name'] as String?,
      theme: theme,
      providers: TileProviders(providers),
      sprites: sprites,
    );
  }

  /// Read tile providers from the style's `sources` map.
  Future<Map<String, VectorTileProvider>> _readProviders({
    required Map sources,
    required String? apiKey,
    required String keyParam,
  }) async {
    // Build (name, future) pairs for all recognised sources, fetching in parallel.
    final futures = <String, Future<VectorTileProvider?>>{};

    for (final entry in sources.entries) {
      final sourceType = entry.value['type'] as String?;
      final type = TileProviderType.values
          .where((e) => e.name.replaceAll('_', '-') == sourceType)
          .firstOrNull;
      if (type == null) continue;

      futures[entry.key as String] = _readSingleProvider(
        entry.value, apiKey, keyParam,
      );
    }

    final results = await Future.wait(
      futures.entries.map((e) async => MapEntry(e.key, await e.value)),
    );

    final providers = <String, VectorTileProvider>{};
    for (final entry in results) {
      if (entry.value != null) providers[entry.key] = entry.value!;
    }

    if (providers.isEmpty) {
      throw StateError('No tile sources found in style');
    }
    return providers;
  }

  /// Resolve a single source entry into a [VectorTileProvider], or null.
  Future<VectorTileProvider?> _readSingleProvider(
    dynamic sourceValue,
    String? apiKey,
    String keyParam,
  ) async {
    Map<String, dynamic> source;
    final entryUrl = sourceValue['url'] as String?;

    if (entryUrl != null) {
      var sourceUrl = entryUrl;
      if (apiKey != null && apiKey.isNotEmpty) {
        sourceUrl = _appendApiKey(sourceUrl, apiKey, keyParam);
      }
      debugPrint('[VectorStyleService] Fetching TileJSON: ${_safeUrl(sourceUrl)}');
      final sourceText = await _httpGet(sourceUrl);
      source = jsonDecode(sourceText) as Map<String, dynamic>;
    } else {
      source = Map<String, dynamic>.from(sourceValue as Map);
    }

    final tiles = source['tiles'];
    final maxzoom = source['maxzoom'] as int? ?? 14;
    final minzoom = source['minzoom'] as int? ?? 1;

    if (tiles is List && tiles.isNotEmpty) {
      var tileUrl = tiles[0] as String;
      if (apiKey != null && apiKey.isNotEmpty) {
        tileUrl = _appendApiKey(tileUrl, apiKey, keyParam);
      }
      debugPrint('[VectorStyleService] Tile URL: ${_safeUrl(tileUrl)}');
      return NetworkVectorTileProvider(
        urlTemplate: tileUrl,
        maximumZoom: maxzoom,
        minimumZoom: minzoom,
      );
    }
    return null;
  }

  /// Read sprite data from the style JSON.
  Future<SpriteStyle?> _readSprites({
    required Map<String, dynamic> styleJson,
    required String? apiKey,
    required String keyParam,
  }) async {
    final spriteUri = styleJson['sprite'] as String?;
    if (spriteUri == null || spriteUri.trim().isEmpty) return null;

    var resolvedSpriteBase = spriteUri;
    if (apiKey != null && apiKey.isNotEmpty) {
      resolvedSpriteBase = _appendApiKey(spriteUri, apiKey, keyParam);
    }

    // Try @2x first (high-DPI), then regular
    for (final suffix in ['@2x', '']) {
      try {
        final jsonUrl = _insertSuffix(resolvedSpriteBase, suffix, '.json');
        final spriteText = await _httpGet(jsonUrl);
        final spriteJson = jsonDecode(spriteText);

        final imageUrl = _insertSuffix(resolvedSpriteBase, suffix, '.png');
        final atlasBytes = await _httpGetBytes(imageUrl);
        return SpriteStyle(
          atlasProvider: () => Future.value(atlasBytes),
          index: SpriteIndexReader(logger: const Logger.noop()).read(spriteJson),
        );
      } catch (e) {
        debugPrint('[VectorStyleService] Sprite $suffix failed: $e');
        continue;
      }
    }
    return null;
  }

  /// Insert a suffix and extension before query parameters.
  ///
  /// e.g. `https://host/sprite?key=x` + `@2x` + `.json`
  ///   → `https://host/sprite@2x.json?key=x`
  String _insertSuffix(String url, String suffix, String extension) {
    final uri = Uri.parse(url);
    final authority = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    final base = '${uri.scheme}://$authority${uri.path}$suffix$extension';
    if (uri.query.isNotEmpty) {
      return '$base?${uri.query}';
    }
    return base;
  }

  Future<String> _httpGet(String url) async {
    final response = await _httpClient.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return response.body;
    }
    // Don't include full URL in exception — it may contain API keys.
    throw HttpException('HTTP ${response.statusCode}: ${_safeUrl(url)}');
  }

  Future<Uint8List> _httpGetBytes(String url) async {
    final response = await _httpClient.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
    throw HttpException('HTTP ${response.statusCode}: ${_safeUrl(url)}');
  }
}
