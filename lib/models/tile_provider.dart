enum TileProviderType {
  osmStreet,
  googleHybrid,
  arcgisSatellite,
  mapboxSatellite,
}

class TileProviderConfig {
  final TileProviderType type;
  final String name;
  final String urlTemplate;
  final String attribution;
  final bool requiresApiKey;
  final String? description;
  
  const TileProviderConfig({
    required this.type,
    required this.name, 
    required this.urlTemplate,
    required this.attribution,
    this.requiresApiKey = false,
    this.description,
  });

  /// Returns the URL template with API key inserted if needed
  String getUrlTemplate({String? apiKey}) {
    if (requiresApiKey && apiKey != null) {
      return urlTemplate.replaceAll('{api_key}', apiKey);
    }
    return urlTemplate;
  }

  /// Check if this provider is available (has required API key if needed)
  bool isAvailable({String? apiKey}) {
    if (requiresApiKey) {
      return apiKey != null && apiKey.isNotEmpty;
    }
    return true;
  }
}

/// Built-in tile provider configurations
class TileProviders {
  static const osmStreet = TileProviderConfig(
    type: TileProviderType.osmStreet,
    name: 'Street Map',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap contributors',
    description: 'Standard street map with roads, buildings, and labels',
  );

  static const googleHybrid = TileProviderConfig(
    type: TileProviderType.googleHybrid,
    name: 'Satellite + Roads',
    urlTemplate: 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
    attribution: '© Google',
    description: 'Satellite imagery with road and label overlays',
  );

  static const arcgisSatellite = TileProviderConfig(
    type: TileProviderType.arcgisSatellite,
    name: 'Pure Satellite',
    urlTemplate: 'https://services.arcgisonline.com/ArcGis/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}.png',
    attribution: '© Esri © Maxar',
    description: 'High-resolution satellite imagery without overlays',
  );

  static const mapboxSatellite = TileProviderConfig(
    type: TileProviderType.mapboxSatellite,
    name: 'Pure Satellite (Mapbox)',
    urlTemplate: 'https://api.mapbox.com/v4/mapbox.satellite/{z}/{x}/{y}@2x.jpg90?access_token={api_key}',
    attribution: '© Mapbox © Maxar',
    requiresApiKey: true,
    description: 'High-resolution satellite imagery without overlays',
  );

  /// Get all available tile providers (those with API keys if required)
  static List<TileProviderConfig> getAvailable({String? mapboxApiKey}) {
    return [
      osmStreet,
      googleHybrid,
      arcgisSatellite,
      if (mapboxSatellite.isAvailable(apiKey: mapboxApiKey)) mapboxSatellite,
    ];
  }

  /// Get provider config by type
  static TileProviderConfig? getByType(TileProviderType type) {
    switch (type) {
      case TileProviderType.osmStreet:
        return osmStreet;
      case TileProviderType.googleHybrid:
        return googleHybrid;
      case TileProviderType.arcgisSatellite:
        return arcgisSatellite;
      case TileProviderType.mapboxSatellite:
        return mapboxSatellite;
    }
  }
}