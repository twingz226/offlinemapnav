/// Central tile server configuration.
///
/// Using Carto basemaps instead of tile.openstreetmap.org because OSM's
/// tile server enforces strict usage policies and frequently returns
/// "Access Blocked" tile images for mobile app usage. Carto basemaps are
/// free, reliable, and designed for application embedding.
class TileConfig {
  TileConfig._();

  /// Primary tile URL template (Carto Voyager — colorful, detailed).
  static const String urlTemplate =
      'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png';

  /// Light variant for light-theme maps.
  static const String urlTemplateLight =
      'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png';

  /// Dark variant for dark-theme maps.
  static const String urlTemplateDark =
      'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png';

  /// User-Agent header value (required by most tile servers).
  static const String userAgent =
      'OfflineNavigator/1.0 (com.offlinenavigator.app; contact@offlinenavigator.app)';

  /// The FMTC store name used for all tile caching.
  static const String storeName = 'offlineMapStore';
}
