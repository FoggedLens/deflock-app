import 'dart:convert';
import 'dart:typed_data';

import '../keys.dart';
import '../services/service_policy.dart';

/// Placeholder token in URL templates that gets replaced with the actual API key.
const kApiKeyPlaceholder = '{api_key}';

/// Whether a tile type serves raster (PNG/JPEG) or vector (style JSON) tiles.
enum TileSourceType {
  rasterXyz,
  vectorStyle,
}

/// A specific tile type within a provider
class TileType {
  final String id;
  final String name;
  final String urlTemplate;
  final String attribution;
  final Uint8List? previewTile; // Single tile image data for preview
  final int maxZoom; // Maximum zoom level for this tile type
  final TileSourceType sourceType;
  final String? styleUrl; // Vector style JSON URL (for vectorStyle types)

  TileType({
    required this.id,
    required this.name,
    required this.urlTemplate,
    required this.attribution,
    this.previewTile,
    this.maxZoom = 18, // Default max zoom level
    this.sourceType = TileSourceType.rasterXyz,
    this.styleUrl,
  });

  /// Whether this tile type uses vector tiles.
  bool get isVector => sourceType == TileSourceType.vectorStyle;

  /// Whether this tile type uses raster tiles.
  bool get isRaster => sourceType == TileSourceType.rasterXyz;

  /// Create URL for a specific tile, replacing template variables
  /// 
  /// Supported placeholders:
  /// - {x}, {y}, {z}: Standard tile coordinates
  /// - {quadkey}: Bing Maps quadkey format (alternative to x/y/z)
  /// - {0_3}: Subdomain 0-3 for load balancing
  /// - {1_4}: Subdomain 1-4 for providers that use 1-based indexing
  /// - {api_key}: API key placeholder (optional)
  String getTileUrl(int z, int x, int y, {String? apiKey}) {
    String url = urlTemplate;
    
    // Handle Bing Maps quadkey conversion
    if (url.contains('{quadkey}')) {
      final quadkey = _convertToQuadkey(x, y, z);
      url = url.replaceAll('{quadkey}', quadkey);
    }
    
    // Handle subdomains for load balancing
    if (url.contains('{0_3}')) {
      final subdomain = (x + y) % 4; // 0, 1, 2, 3
      url = url.replaceAll('{0_3}', subdomain.toString());
    }
    
    if (url.contains('{1_4}')) {
      final subdomain = ((x + y) % 4) + 1; // 1, 2, 3, 4
      url = url.replaceAll('{1_4}', subdomain.toString());
    }
    
    // Standard x/y/z replacement
    url = url
        .replaceAll('{z}', z.toString())
        .replaceAll('{x}', x.toString())
        .replaceAll('{y}', y.toString());
    
    if (apiKey != null && apiKey.isNotEmpty) {
      url = url.replaceAll(kApiKeyPlaceholder, apiKey);
    }
    
    return url;
  }

  /// Convert x, y, z to Bing Maps quadkey format
  String _convertToQuadkey(int x, int y, int z) {
    final quadkey = StringBuffer();
    for (int i = z; i > 0; i--) {
      int digit = 0;
      final mask = 1 << (i - 1);
      if ((x & mask) != 0) digit++;
      if ((y & mask) != 0) digit += 2;
      quadkey.write(digit);
    }
    return quadkey.toString();
  }

  /// Check if this tile type needs an API key
  bool get requiresApiKey => urlTemplate.contains(kApiKeyPlaceholder);

  /// The service policy that applies to this tile type's server.
  /// Cached because [urlTemplate] is immutable.
  late final ServicePolicy servicePolicy =
      ServicePolicyResolver.resolve(urlTemplate);

  /// Whether this tile server's usage policy permits offline/bulk downloading.
  /// Always false for vector tile types (offline download not yet supported).
  /// For raster types, resolved via [ServicePolicyResolver] from the URL template.
  bool get allowsOfflineDownload =>
      isVector ? false : servicePolicy.allowsOfflineDownload;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'urlTemplate': urlTemplate,
    'attribution': attribution,
    'previewTile': previewTile != null ? base64Encode(previewTile!) : null,
    'maxZoom': maxZoom,
    if (sourceType != TileSourceType.rasterXyz)
      'sourceType': sourceType.name,
    if (styleUrl != null) 'styleUrl': styleUrl,
  };

  static TileType fromJson(Map<String, dynamic> json) {
    final sourceTypeName = json['sourceType'] as String?;
    final sourceType = sourceTypeName != null
        ? TileSourceType.values.firstWhere(
            (e) => e.name == sourceTypeName,
            orElse: () => TileSourceType.rasterXyz,
          )
        : TileSourceType.rasterXyz;

    return TileType(
      id: json['id'],
      name: json['name'],
      urlTemplate: json['urlTemplate'],
      attribution: json['attribution'],
      previewTile: json['previewTile'] != null
          ? base64Decode(json['previewTile'])
          : null,
      maxZoom: json['maxZoom'] ?? 18,
      sourceType: sourceType,
      styleUrl: json['styleUrl'],
    );
  }

  TileType copyWith({
    String? id,
    String? name,
    String? urlTemplate,
    String? attribution,
    Uint8List? previewTile,
    int? maxZoom,
    TileSourceType? sourceType,
    String? styleUrl,
  }) => TileType(
    id: id ?? this.id,
    name: name ?? this.name,
    urlTemplate: urlTemplate ?? this.urlTemplate,
    attribution: attribution ?? this.attribution,
    previewTile: previewTile ?? this.previewTile,
    maxZoom: maxZoom ?? this.maxZoom,
    sourceType: sourceType ?? this.sourceType,
    styleUrl: styleUrl ?? this.styleUrl,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TileType && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A tile provider containing multiple tile types
class TileProvider {
  final String id;
  final String name;
  final String? apiKey;
  final List<TileType> tileTypes;

  const TileProvider({
    required this.id,
    required this.name,
    this.apiKey,
    required this.tileTypes,
  });

  /// Check if this provider is usable (has API key if any tile types need it)
  bool get isUsable {
    final needsKey = tileTypes.any((type) => type.requiresApiKey);
    return !needsKey || (apiKey != null && apiKey!.isNotEmpty);
  }

  /// Get available tile types (those that don't need API key or have one)
  List<TileType> get availableTileTypes {
    return tileTypes.where((type) => !type.requiresApiKey || isUsable).toList();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'apiKey': apiKey,
    'tileTypes': tileTypes.map((type) => type.toJson()).toList(),
  };

  static TileProvider fromJson(Map<String, dynamic> json) => TileProvider(
    id: json['id'],
    name: json['name'],
    apiKey: json['apiKey'],
    tileTypes: (json['tileTypes'] as List)
        .map((typeJson) => TileType.fromJson(typeJson))
        .toList(),
  );

  TileProvider copyWith({
    String? id,
    String? name,
    String? apiKey,
    List<TileType>? tileTypes,
  }) => TileProvider(
    id: id ?? this.id,
    name: name ?? this.name,
    apiKey: apiKey ?? this.apiKey,
    tileTypes: tileTypes ?? this.tileTypes,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TileProvider && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Factory for creating default tile providers
class DefaultTileProviders {
  /// Create the default set of tile providers
  static List<TileProvider> createDefaults() {
    return [
      TileProvider(
        id: 'openstreetmap',
        name: 'OpenStreetMap',
        tileTypes: [
          TileType(
            id: 'osm_street',
            name: 'Street Map',
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            attribution: '© OpenStreetMap contributors',
            maxZoom: 19,
          ),
        ],
      ),
      TileProvider(
        id: 'bing',
        name: 'Bing Maps',
        tileTypes: [
          TileType(
            id: 'bing_satellite',
            name: 'Satellite',
            urlTemplate: 'https://ecn.t{0_3}.tiles.virtualearth.net/tiles/a{quadkey}.jpeg?g=1&n=z',
            attribution: '© Microsoft Corporation',
            maxZoom: 20,
          ),
        ],
      ),
      TileProvider(
        id: 'mapbox',
        name: 'Mapbox',
        tileTypes: [
          TileType(
            id: 'mapbox_satellite',
            name: 'Satellite',
            urlTemplate: 'https://api.mapbox.com/v4/mapbox.satellite/{z}/{x}/{y}@2x.jpg90?access_token={api_key}',
            attribution: '© Mapbox © Maxar',
          ),
          TileType(
            id: 'mapbox_streets',
            name: 'Streets',
            urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}?access_token={api_key}',
            attribution: '© Mapbox © OpenStreetMap',
          ),
        ],
      ),
      TileProvider(
        id: 'opentopomap_memomaps',
        name: 'OpenTopoMap/Memomaps',
        tileTypes: [
          TileType(
            id: 'opentopomap_topo',
            name: 'Topographic',
            urlTemplate: 'https://tile.memomaps.de/tilegen/{z}/{x}/{y}.png',
            attribution: 'Kartendaten: © OpenStreetMap-Mitwirkende, SRTM | Kartendarstellung: © OpenTopoMap (CC-BY-SA)',
            maxZoom: 18,
          ),
        ],
      ),
      TileProvider(
        id: 'stadiamaps_vector',
        name: 'Stadia Maps (Vector)',
        apiKey: kStadiaApiKey.isNotEmpty ? kStadiaApiKey : null,
        tileTypes: [
          TileType(
            id: 'stadia_osm_bright',
            name: 'OSM Bright',
            urlTemplate: 'https://tiles.stadiamaps.com/styles/osm_bright.json?api_key={api_key}',
            attribution: '© Stadia Maps © OpenMapTiles © OpenStreetMap contributors',
            maxZoom: 20,
            sourceType: TileSourceType.vectorStyle,
            styleUrl: 'https://tiles.stadiamaps.com/styles/osm_bright.json?api_key={api_key}',
          ),
        ],
      ),
      TileProvider(
        id: 'maptiler_vector',
        name: 'MapTiler (Vector)',
        tileTypes: [
          TileType(
            id: 'maptiler_streets',
            name: 'Streets',
            urlTemplate: 'https://api.maptiler.com/maps/streets-v2/style.json?key={api_key}',
            attribution: '© MapTiler © OpenStreetMap contributors',
            maxZoom: 20,
            sourceType: TileSourceType.vectorStyle,
            styleUrl: 'https://api.maptiler.com/maps/streets-v2/style.json?key={api_key}',
          ),
        ],
      ),
    ];
  }
}

