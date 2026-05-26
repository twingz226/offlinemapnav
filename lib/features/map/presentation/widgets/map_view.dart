import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/constants/tile_config.dart';
import '../../data/models/favorite_place_model.dart';
import 'user_location_indicator.dart';

enum MapOrientationMode { northUp, headingUp, navigation3D }

class MapView extends StatefulWidget {
  final List<FavoritePlaceModel> favorites;
  final List<FavoritePlaceModel> categoryPlaces;
  final String? selectedCategory;
  final FavoritePlaceModel? selectedPlace;
  final void Function(FavoritePlaceModel place)? onPlaceSelected;
  final Position? userPosition;
  final MapController? mapController;
  final void Function(TapPosition tapPosition, LatLng point)? onTap;
  final List<LatLng>? routePolyline;
  final List<List<LatLng>>? alternativePolylines;
  final void Function(LatLng center, LatLngBounds bounds, double zoom)? onViewportChanged;
  final bool isNavigating;
  final MapOrientationMode orientationMode;
  final bool isDarkTheme;

  const MapView({
    super.key,
    required this.favorites,
    required this.categoryPlaces,
    this.selectedCategory,
    this.selectedPlace,
    this.onPlaceSelected,
    this.userPosition,
    this.mapController,
    this.onTap,
    this.routePolyline,
    this.alternativePolylines,
    this.onViewportChanged,
    this.isNavigating = false,
    this.orientationMode = MapOrientationMode.northUp,
    this.isDarkTheme = false,
  });

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> with SingleTickerProviderStateMixin {
  LatLngBounds? _visibleBounds;
  double _mapRotation = 0.0;

  // Construct the tile provider ONCE outside of build() to avoid
  // performance issues and internal image cache disruption.
  late final FMTCTileProvider _tileProvider;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    // Explicit cacheFirst settings: serve cached tiles first, only fetch from
    // network if cached tile is expired. This ensures downloaded tiles display
    // correctly even when fully offline.
    final settings = FMTCTileProviderSettings(
      behavior: CacheBehavior.cacheFirst,
      cachedValidDuration: const Duration(days: 30),
      fallbackToAlternativeStore: true,
      errorHandler: (error) {
        // Silently handle FMTC browsing errors (e.g. tile missing in cache
        // while offline) — the TileLayer's evictErrorTileStrategy will show
        // a placeholder instead of crashing.
        debugPrint('FMTC browsing error: ${error.type}');
      },
    );
    _tileProvider = const FMTCStore(TileConfig.storeName).getTileProvider(
      settings: settings,
      headers: {
        'User-Agent': TileConfig.userAgent,
      },
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _tileProvider.dispose();
    super.dispose();
  }

  String? _detectCategory(FavoritePlaceModel place) {
    final name = place.name.toLowerCase();
    final desc = place.description.toLowerCase();
    if (name.contains('beach') || desc.contains('beach') || name.contains('sandbar') || desc.contains('sandbar')) {
      return 'beaches';
    }
    if (name.contains('falls') || desc.contains('falls') || name.contains('waterfall') || desc.contains('waterfall')) {
      return 'falls';
    }
    if (name.contains('pool') || desc.contains('pool') || name.contains('waterpark') || desc.contains('waterpark')) {
      return 'pools';
    }
    if (name.contains('spring') || desc.contains('spring')) {
      return 'springs';
    }
    if (name.contains('camp') || desc.contains('camp')) {
      return 'camps';
    }
    return null;
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'beaches':
        return Icons.beach_access;
      case 'falls':
        return Icons.water;
      case 'pools':
        return Icons.pool;
      case 'springs':
        return Icons.hot_tub;
      case 'camps':
        return Icons.forest;
      default:
        return Icons.location_pin;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'beaches':
        return Colors.cyan.shade700;
      case 'falls':
        return Colors.blue.shade700;
      case 'pools':
        return Colors.indigo.shade600;
      case 'springs':
        return Colors.teal.shade600;
      case 'camps':
        return Colors.green.shade700;
      default:
        return Colors.red;
    }
  }

  // ── Road styling colours ──────────────────────────────────────────────
  // Main roads / highways → red tones
  // Secondary & other roads → navy blue tones
  // Colours are tuned for visibility on both light and dark Carto basemaps.



  @override
  Widget build(BuildContext context) {
    // Build unique list of places to render
    final allRenderedPlaces = <String, (FavoritePlaceModel, bool)>{};
    
    for (final place in widget.favorites) {
      final key = '${place.name}_${place.latitude.toStringAsFixed(5)}_${place.longitude.toStringAsFixed(5)}';
      allRenderedPlaces[key] = (place, false);
    }
    
    for (final place in widget.categoryPlaces) {
      final key = '${place.name}_${place.latitude.toStringAsFixed(5)}_${place.longitude.toStringAsFixed(5)}';
      allRenderedPlaces[key] = (place, true);
    }

    final visiblePlaces = allRenderedPlaces.values.where((item) {
      if (_visibleBounds == null) return true;
      final latLng = LatLng(item.$1.latitude, item.$1.longitude);
      return _visibleBounds!.contains(latLng);
    }).toList();

    final markers = visiblePlaces.map((entry) {
      final place = entry.$1;
      final isCategory = entry.$2;
      
      final isSelected = widget.selectedPlace != null &&
          widget.selectedPlace!.latitude == place.latitude &&
          widget.selectedPlace!.longitude == place.longitude;

      final Color markerColor;
      final IconData markerIcon;
      
      if (isSelected) {
        markerColor = Colors.orange.shade800;
        markerIcon = Icons.star;
      } else if (isCategory && widget.selectedCategory != null) {
        markerColor = _getCategoryColor(widget.selectedCategory!);
        markerIcon = _getCategoryIcon(widget.selectedCategory!);
      } else {
        final matchedCategory = _detectCategory(place);
        if (matchedCategory != null) {
          markerColor = _getCategoryColor(matchedCategory);
          markerIcon = _getCategoryIcon(matchedCategory);
        } else {
          markerColor = Colors.red;
          markerIcon = Icons.favorite;
        }
      }

      return Marker(
        point: LatLng(place.latitude, place.longitude),
        width: isSelected ? 50.0 : 42.0,
        height: isSelected ? 50.0 : 42.0,
        child: GestureDetector(
          onTap: () {
            if (widget.onPlaceSelected != null) {
              widget.onPlaceSelected!(place);
            }
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (isSelected)
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      width: 36 + (14 * _pulseController.value),
                      height: 36 + (14 * _pulseController.value),
                      decoration: BoxDecoration(
                        color: markerColor.withValues(alpha: 0.3 * (1.0 - _pulseController.value)),
                        shape: BoxShape.circle,
                      ),
                    );
                  },
                ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  border: Border.all(
                    color: markerColor,
                    width: isSelected ? 3.0 : 2.0,
                  ),
                ),
                padding: const EdgeInsets.all(6),
                child: Icon(
                  markerIcon,
                  size: isSelected ? 24 : 20,
                  color: markerColor,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();

    Widget mapWidget = FlutterMap(
      mapController: widget.mapController,
      options: MapOptions(
        initialCenter: const LatLng(9.3068, 123.3054),
        initialZoom: 13,
        onTap: widget.onTap,
        onPositionChanged: (position, hasGesture) {
          setState(() {
            _visibleBounds = position.visibleBounds;
            _mapRotation = position.rotation;
          });
          if (widget.onViewportChanged != null) {
            widget.onViewportChanged!(position.center, position.visibleBounds, position.zoom);
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: TileConfig.urlTemplate,
          tileProvider: _tileProvider,
          panBuffer: 1,
          keepBuffer: 5,
          // When a tile fetch fails (offline + not cached), don't permanently
          // evict it — retry on the next map move so tiles appear once the
          // cache or network becomes available.
          evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
          userAgentPackageName: 'com.offlinenavigator.app',
          // Show a subtle placeholder for tiles that fail to load (e.g. not
          // cached and offline), instead of a hard error.
          errorTileCallback: (tile, error, stackTrace) {
            debugPrint('Tile load error at ${tile.coordinates}: $error');
          },
        ),

        if (widget.alternativePolylines != null && widget.alternativePolylines!.isNotEmpty)
          PolylineLayer(
            polylines: widget.alternativePolylines!.map((polylinePoints) {
              return Polyline(
                points: polylinePoints,
                strokeWidth: 4.5,
                color: Colors.grey.withValues(alpha: 0.65),
                borderColor: Colors.grey[700] ?? Colors.grey,
                borderStrokeWidth: 1.0,
              );
            }).toList(),
          ),
        if (widget.routePolyline != null && widget.routePolyline!.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.routePolyline!,
                strokeWidth: 5.5,
                color: Colors.blueAccent,
                borderColor: Colors.blue[900] ?? Colors.blue,
                borderStrokeWidth: 1.5,
              ),
            ],
          ),
        MarkerClusterLayerWidget(
          options: MarkerClusterLayerOptions(
            maxClusterRadius: 45,
            size: const Size(40, 40),
            markers: markers,
            builder: (context, cluster) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    cluster.length.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.userPosition != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(
                  widget.userPosition!.latitude,
                  widget.userPosition!.longitude,
                ),
                width: 160,
                height: 160,
                rotate: true, // Counter-rotates marker to keep it oriented with map North
                child: UserLocationIndicator(
                  userPosition: widget.userPosition,
                  isNavigating: widget.isNavigating,
                  mapRotation: _mapRotation,
                ),
              ),
            ],
          ),
      ],
    );

    if (widget.orientationMode == MapOrientationMode.navigation3D) {
      mapWidget = ClipRect(
        child: Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0015) // perspective depth
            ..rotateX(0.7), // tilt forward by ~40 degrees
          alignment: Alignment.center,
          child: FractionallySizedBox(
            heightFactor: 1.45, // expand map height to cover empty margins due to 3D tilt
            child: mapWidget,
          ),
        ),
      );
    }

    return mapWidget;
  }
}
