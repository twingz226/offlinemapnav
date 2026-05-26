import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'package:flutter_compass/flutter_compass.dart';
import 'hud_navigation_page.dart';


import '../widgets/map_view.dart';
import '../widgets/auto_download_overlay.dart';
import '../providers/location_provider.dart';
import '../providers/auto_download_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/search_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/trip_recorder_provider.dart';
import '../../data/models/favorite_place_model.dart';
import '../../services/routing_service.dart';
import '../../services/distance_service.dart';
import '../../services/poi_service.dart';

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});

  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> with SingleTickerProviderStateMixin {
  late final MapController _mapController;
  late final TextEditingController _searchController;
  FavoritePlaceModel? _selectedPlace;
  String? _selectedCategory;
  List<FavoritePlaceModel> _onlineCategoryPlaces = [];
  bool _isLoadingCategoryPlaces = false;
  LatLng? _currentMapCenter;

  MapOrientationMode _orientationMode = MapOrientationMode.northUp;
  StreamSubscription<CompassEvent>? _compassSubscription;
  
  late final AnimationController _recordPulseController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _searchController = TextEditingController();
    _startCompassListening();
    _recordPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _recordPulseController.dispose();
    _compassSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleTripRecordingToggle() async {
    final recorder = ref.read(tripRecorderProvider.notifier);
    final state = ref.read(tripRecorderProvider);

    if (state.isRecording) {
      recorder.stopRecording();
      final nameController = TextEditingController(
        text: 'Trip on ${DateTime.now().toString().substring(0, 16)}',
      );
      final tripName = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Save Recorded Trip'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Do you want to save this trip log? You can review statistics in settings.'),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Trip Name',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                recorder.discardRecording();
                Navigator.pop(context);
              },
              child: const Text('Discard', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, nameController.text),
              child: const Text('Save'),
            ),
          ],
        ),
      );

      if (tripName != null && tripName.trim().isNotEmpty) {
        final path = await recorder.saveCurrentTrip(tripName);
        if (path != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Trip "$tripName" saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recording discarded (no GPS points captured).'),
            ),
          );
        }
      }
    } else {
      recorder.startRecording();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Trip recording started.'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  void _startCompassListening() {
    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (!mounted) return;
      final heading = event.heading;
      if (heading != null) {
        // Rotate map dynamically when locked to heading modes
        if (_orientationMode == MapOrientationMode.headingUp ||
            _orientationMode == MapOrientationMode.navigation3D) {
          final userPos = ref.read(locationProvider).value;
          final isMoving = (userPos?.speed ?? 0.0) > 1.0;
          final double activeHeading = isMoving ? (userPos?.heading ?? 0.0) : heading;
          _mapController.rotate(-activeHeading);
        }
      }
    });
  }

  void _toggleOrientationMode() {
    setState(() {
      switch (_orientationMode) {
        case MapOrientationMode.northUp:
          _orientationMode = MapOrientationMode.headingUp;
          break;
        case MapOrientationMode.headingUp:
          _orientationMode = MapOrientationMode.navigation3D;
          break;
        case MapOrientationMode.navigation3D:
          _orientationMode = MapOrientationMode.northUp;
          _mapController.rotate(0.0);
          break;
      }
    });
  }

  Future<void> _centerOnUser() async {
    // 1. Instantly center on last known location if cached
    final lastPos = await ref.read(locationProvider.notifier).getLastKnownLocation();
    if (lastPos != null && mounted) {
      _mapController.move(LatLng(lastPos.latitude, lastPos.longitude), 15.0);
    }

    // 2. Fetch fresh high-accuracy position in the background
    final freshPos = await ref.read(locationProvider.notifier).getCurrentLocation();
    if (freshPos != null && mounted) {
      _mapController.move(LatLng(freshPos.latitude, freshPos.longitude), 15.0);
    } else if (lastPos == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to retrieve location. Make sure GPS is enabled.'),
          ),
        );
      }
    }
  }

  IconData _getTurnIcon(String instruction) {
    final lower = instruction.toLowerCase();
    if (lower.contains('left')) {
      if (lower.contains('bear') || lower.contains('slight')) return Icons.turn_slight_left;
      if (lower.contains('sharp')) return Icons.turn_sharp_left;
      return Icons.turn_left;
    }
    if (lower.contains('right')) {
      if (lower.contains('bear') || lower.contains('slight')) return Icons.turn_slight_right;
      if (lower.contains('sharp')) return Icons.turn_sharp_right;
      return Icons.turn_right;
    }
    if (lower.contains('arrive')) {
      return Icons.sports_score;
    }
    if (lower.contains('depart')) {
      return Icons.my_location;
    }
    return Icons.navigation;
  }

  List<FavoritePlaceModel> _getCategoryPlaces() {
    if (_selectedCategory == null) return [];

    final categoryLower = _selectedCategory!.toLowerCase();
    
    // 1. Get built-in spots matching this category
    final localPOIs = POIService.getPlacesByCategory(categoryLower);

    // 2. Filter user favorites matching this category keywords
    final favorites = ref.read(favoritesProvider);
    final matchingFavorites = favorites.where((place) {
      final name = place.name.toLowerCase();
      final desc = place.description.toLowerCase();

      switch (categoryLower) {
        case 'beaches':
          return name.contains('beach') || desc.contains('beach') || name.contains('sandbar') || desc.contains('sandbar');
        case 'falls':
          return name.contains('falls') || desc.contains('falls') || name.contains('waterfall') || desc.contains('waterfall');
        case 'pools':
          return name.contains('pool') || desc.contains('pool') || name.contains('waterpark') || desc.contains('waterpark');
        case 'springs':
          return name.contains('spring') || desc.contains('spring');
        case 'camps':
          return name.contains('camp') || desc.contains('camp');
        case 'food':
          return name.contains('restaurant') || desc.contains('restaurant') || name.contains('cafe') || desc.contains('cafe') || name.contains('pastries') || name.contains('inato') || name.contains('bar') || name.contains('bistro') || name.contains('diner') || name.contains('eatery');
        case 'gas':
          return name.contains('petron') || name.contains('shell') || name.contains('caltex') || name.contains('seaoil') || name.contains('gas') || desc.contains('gasoline') || desc.contains('fuel');
        case 'lodging':
          return name.contains('hotel') || desc.contains('hotel') || name.contains('resort') || desc.contains('resort') || name.contains('suites') || name.contains('mansion') || name.contains('hostel') || name.contains('bed and breakfast');
        case 'medical':
          return name.contains('medical') || desc.contains('medical') || name.contains('hospital') || desc.contains('hospital') || name.contains('clinic') || name.contains('drug') || name.contains('pharmacy');
        case 'shopping':
          return name.contains('mall') || desc.contains('mall') || name.contains('plaza') || name.contains('super') || name.contains('market') || name.contains('store');
        default:
          return false;
      }
    }).toList();

    final allPlaces = [
      ...matchingFavorites,
      ...localPOIs,
      ..._onlineCategoryPlaces,
    ];

    final uniquePlaces = <String, FavoritePlaceModel>{};
    for (final p in allPlaces) {
      uniquePlaces['${p.name.trim()}_${p.latitude.toStringAsFixed(4)}_${p.longitude.toStringAsFixed(4)}'] = p;
    }

    return uniquePlaces.values.toList();
  }

  Future<void> _fetchOnlineCategoryPlaces(String category) async {
    setState(() {
      _isLoadingCategoryPlaces = true;
    });

    try {
      final dio = Dio();
      dio.options.headers['User-Agent'] = 'OfflineNavigatorApp/1.0.0';
      dio.options.connectTimeout = const Duration(seconds: 5);
      dio.options.receiveTimeout = const Duration(seconds: 5);

      final userPos = ref.read(locationProvider).value;
      
      String queryTerm = category;
      switch (category.toLowerCase()) {
        case 'beaches':
          queryTerm = 'beach';
          break;
        case 'falls':
          queryTerm = 'waterfall';
          break;
        case 'pools':
          queryTerm = 'swimming pool';
          break;
        case 'springs':
          queryTerm = 'spring';
          break;
        case 'camps':
          queryTerm = 'camp site';
          break;
        case 'food':
          queryTerm = 'restaurant';
          break;
        case 'gas':
          queryTerm = 'gas station';
          break;
        case 'lodging':
          queryTerm = 'hotel';
          break;
        case 'medical':
          queryTerm = 'hospital';
          break;
        case 'shopping':
          queryTerm = 'mall';
          break;
      }

      final queryParams = {
        'q': queryTerm,
        'format': 'json',
        'limit': 15,
        'addressdetails': 1,
      };

      final centerLat = userPos?.latitude ?? 9.3068;
      final centerLng = userPos?.longitude ?? 123.3054;
      queryParams['lat'] = centerLat.toString();
      queryParams['lon'] = centerLng.toString();

      final response = await dio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200 && response.data is List && mounted) {
        final List results = response.data;
        final places = results.map((item) {
          final displayName = item['display_name'] as String;
          final parts = displayName.split(',');
          final name = parts.isNotEmpty ? parts[0] : displayName;
          final description = parts.length > 1 ? parts.sublist(1).join(',').trim() : displayName;

          return FavoritePlaceModel(
            name: name,
            latitude: double.parse(item['lat'] as String),
            longitude: double.parse(item['lon'] as String),
            description: description,
          );
        }).toList();

        setState(() {
          _onlineCategoryPlaces = places;
        });
      }
    } catch (e) {
      debugPrint('Error fetching online category places: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCategoryPlaces = false;
        });
      }
    }
  }

  void _centerOnPlaces(List<FavoritePlaceModel> places) {
    if (places.isEmpty) return;
    if (places.length == 1) {
      _mapController.move(LatLng(places.first.latitude, places.first.longitude), 14.5);
      return;
    }

    double minLat = places.first.latitude;
    double maxLat = places.first.latitude;
    double minLng = places.first.longitude;
    double maxLng = places.first.longitude;

    for (final p in places) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(
            LatLng(minLat, minLng),
            LatLng(maxLat, maxLng),
          ),
          padding: const EdgeInsets.all(50.0),
        ),
      );
    } catch (e) {
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;
      _mapController.move(LatLng(centerLat, centerLng), 12.0);
    }
  }

  Widget _buildCategoryRow() {
    final categories = [
      (name: 'Beaches', icon: Icons.beach_access, color: Colors.cyan.shade700),
      (name: 'Falls', icon: Icons.water, color: Colors.blue.shade700),
      (name: 'Pools', icon: Icons.pool, color: Colors.indigo.shade600),
      (name: 'Springs', icon: Icons.hot_tub, color: Colors.teal.shade600),
      (name: 'Camps', icon: Icons.forest, color: Colors.green.shade700),
      (name: 'Food', icon: Icons.restaurant, color: Colors.orange.shade700),
      (name: 'Gas', icon: Icons.local_gas_station, color: Colors.deepOrange.shade700),
      (name: 'Lodging', icon: Icons.hotel, color: Colors.purple.shade700),
      (name: 'Medical', icon: Icons.medical_services, color: Colors.red.shade700),
      (name: 'Shopping', icon: Icons.shopping_bag, color: Colors.pink.shade700),
    ];


    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = _selectedCategory == cat.name;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: Material(
              color: isSelected ? cat.color : Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(22),
              elevation: isSelected ? 4 : 2,
              shadowColor: (isSelected ? cat.color : Colors.black).withValues(alpha: 0.3),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () async {
                  setState(() {
                    if (isSelected) {
                      _selectedCategory = null;
                      _onlineCategoryPlaces = [];
                    } else {
                      _selectedCategory = cat.name;
                    }
                  });

                  if (_selectedCategory != null) {
                    bool isOnline = false;
                    try {
                      final res = await Connectivity().checkConnectivity();
                      isOnline = !res.contains(ConnectivityResult.none);
                    } catch (_) {}
                    if (isOnline) {
                      await _fetchOnlineCategoryPlaces(cat.name);
                    } else {
                      setState(() {
                        _onlineCategoryPlaces = [];
                      });
                    }

                    // Auto-center/fit camera bounds to the matching places
                    final places = _getCategoryPlaces();
                    if (places.isNotEmpty) {
                      _centerOnPlaces(places);
                    }
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        cat.icon,
                        size: 18,
                        color: isSelected ? Colors.white : cat.color,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        cat.name,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      if (isSelected && _isLoadingCategoryPlaces) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) {
      return '$minutes min';
    }
    final hours = minutes ~/ 60;
    final remainingMin = minutes % 60;
    return '${hours}h ${remainingMin}m';
  }

  String _getRouteViaString(RouteInfo route) {
    final Set<String> streets = {};
    for (final step in route.steps) {
      final instr = step.instruction;
      if (instr.contains('onto ')) {
        final street = instr.split('onto ').last.trim();
        if (street.isNotEmpty) streets.add(street);
      } else if (instr.contains('on ')) {
        final street = instr.split('on ').last.trim();
        if (street.isNotEmpty) streets.add(street);
      }
    }
    
    streets.removeWhere((s) => s.toLowerCase().contains('starting') || s.toLowerCase().contains('destination'));

    if (streets.isEmpty) {
      return "Local Roads";
    }
    return "via ${streets.take(2).join(' & ')}";
  }

  bool _isPointNearPolyline(LatLng point, List<LatLng> polyline, double thresholdMeters) {
    for (int i = 0; i < polyline.length - 1; i++) {
      final p1 = polyline[i];
      final p2 = polyline[i + 1];
      
      final double distance = _distanceToSegment(point, p1, p2);
      if (distance <= thresholdMeters) {
        return true;
      }
    }
    return false;
  }

  double _distanceToSegment(LatLng p, LatLng a, LatLng b) {
    final double x = p.longitude;
    final double y = p.latitude;
    final double x1 = a.longitude;
    final double y1 = a.latitude;
    final double x2 = b.longitude;
    final double y2 = b.latitude;

    final double dx = x2 - x1;
    final double dy = y2 - y1;

    if (dx == 0 && dy == 0) {
      return DistanceService.calculateDistance(p, a) * 1000;
    }

    final double t = ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy);

    if (t < 0) {
      return DistanceService.calculateDistance(p, a) * 1000;
    } else if (t > 1) {
      return DistanceService.calculateDistance(p, b) * 1000;
    }

    final LatLng projection = LatLng(
      y1 + t * dy,
      x1 + t * dx,
    );

    return DistanceService.calculateDistance(p, projection) * 1000;
  }

  Widget _buildRouteOptionCard(
    BuildContext context, {
    required RouteInfo route,
    required bool isActive,
    required List<String> badges,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final borderColor = isActive ? Colors.blueAccent : Colors.grey.shade300;
    final backgroundColor = isActive ? Colors.blue.withValues(alpha: 0.05) : theme.colorScheme.surface;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(color: borderColor, width: isActive ? 2.0 : 1.0),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: badges.map((badge) {
                        final isPrimaryBadge = badge.contains("Best") || badge.contains("Fastest") || badge.contains("Shortest");
                        return Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isPrimaryBadge 
                                ? (isActive ? Colors.blueAccent : Colors.green.shade600)
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              color: isPrimaryBadge ? Colors.white : Colors.grey.shade700,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                Icon(
                  isActive ? Icons.check_circle : Icons.circle_outlined,
                  size: 16,
                  color: isActive ? Colors.blueAccent : Colors.grey,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _formatDuration(route.duration),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
            ),
            Text(
              _formatDistance(route.distance),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _getRouteViaString(route),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                overflow: TextOverflow.ellipsis,
              ),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(locationProvider);
    final favorites = ref.watch(favoritesProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final searchResultsAsync = ref.watch(searchResultsProvider);
    final navState = ref.watch(navigationProvider);
    final recorderState = ref.watch(tripRecorderProvider);
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    // Auto center on user location when it first loads successfully
    ref.listen<AsyncValue<Position?>>(locationProvider, (previous, next) {
      next.whenOrNull(
        data: (pos) {
          if (pos != null) {
            final activeNav = ref.read(navigationProvider);
            if (!activeNav.isNavigating && (previous == null || previous.value == null)) {
              _mapController.move(LatLng(pos.latitude, pos.longitude), 15.0);
            }
          }
        },
      );
    });

    ref.listen(navigationProvider, (previous, next) {
      // Auto center camera on the snapped coordinates during active navigation
      if (next.isNavigating && next.snappedPosition != null &&
          (previous == null || previous.snappedPosition != next.snappedPosition)) {
        final pos = next.snappedPosition!;
        _mapController.move(LatLng(pos.latitude, pos.longitude), 16.5);
      }

      if (next.activeRoute != null && (previous == null || previous.activeRoute != next.activeRoute)) {
        final polyline = next.activeRoute!.polyline;
        if (polyline.isNotEmpty) {
          double minLat = polyline.first.latitude;
          double maxLat = polyline.first.latitude;
          double minLng = polyline.first.longitude;
          double maxLng = polyline.first.longitude;

          for (final p in polyline) {
            if (p.latitude < minLat) minLat = p.latitude;
            if (p.latitude > maxLat) maxLat = p.latitude;
            if (p.longitude < minLng) minLng = p.longitude;
            if (p.longitude > maxLng) maxLng = p.longitude;
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              try {
                _mapController.fitCamera(
                  CameraFit.bounds(
                    bounds: LatLngBounds(
                      LatLng(minLat, minLng),
                      LatLng(maxLat, maxLng),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 50.0, vertical: 80.0),
                  ),
                );
              } catch (e) {
                _mapController.move(polyline.first, 14.0);
              }
            }
          });
        }
      }
    });

    final double statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Stack(
        children: [
          MapView(
            favorites: favorites,
            categoryPlaces: _getCategoryPlaces(),
            selectedCategory: _selectedCategory,
            selectedPlace: _selectedPlace,
            onPlaceSelected: (place) {
              setState(() {
                _selectedPlace = place;
              });
              _mapController.move(LatLng(place.latitude, place.longitude), 15.5);
            },
            userPosition: navState.isNavigating && navState.snappedPosition != null
                ? navState.snappedPosition
                : location.value,
            mapController: _mapController,
            routePolyline: navState.activeRoute?.polyline,
            alternativePolylines: navState.alternativeRoutes.map((r) => r.polyline).toList(),
            isNavigating: navState.isNavigating,
            orientationMode: _orientationMode,
            isDarkTheme: isDarkTheme,
            onViewportChanged: (center, bounds, zoom) {
              ref.read(autoDownloadProvider.notifier).onMapPositionChanged(bounds, zoom);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _currentMapCenter = center;
                  });
                }
              });
            },
            onTap: (tapPosition, latlng) {
              if (navState.activeRoute != null && !navState.isNavigating) {
                // Check if tap is near any alternative route
                for (final route in navState.alternativeRoutes) {
                  if (_isPointNearPolyline(latlng, route.polyline, 80.0)) {
                    ref.read(navigationProvider.notifier).selectAlternativeRoute(route);
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Switched route ${_getRouteViaString(route)}'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: Colors.blueAccent,
                      ),
                    );
                    return;
                  }
                }
                return; // Suppress place pinning while selecting routes
              }

              final pinned = FavoritePlaceModel(
                name: 'Pinned Location',
                latitude: latlng.latitude,
                longitude: latlng.longitude,
                description: 'Saved offline location',
              );

              ref.read(favoritesProvider.notifier).addFavorite(pinned);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Location saved offline'),
                ),
              );

              setState(() {
                _selectedPlace = pinned;
              });
            },
          ),

          if (recorderState.isRecording)
            Positioned(
              left: 16,
              top: statusBarHeight + 68,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pulsing Red Dot
                    AnimatedBuilder(
                      animation: _recordPulseController,
                      builder: (context, child) {
                        return Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.3 + 0.7 * _recordPulseController.value),
                            shape: BoxShape.circle,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Recording: ${(recorderState.totalDistance / 1000.0).toStringAsFixed(2)} km',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Location status panel (moved down below the search bar and filter chips if not navigating)
          if (!navState.isNavigating)
            Positioned(
              top: statusBarHeight + 136,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _currentMapCenter != null
                      ? "Lat: ${_currentMapCenter!.latitude.toStringAsFixed(5)}\nLng: ${_currentMapCenter!.longitude.toStringAsFixed(5)}"
                      : (location.value != null
                          ? "Lat: ${location.value!.latitude.toStringAsFixed(5)}\nLng: ${location.value!.longitude.toStringAsFixed(5)}"
                          : "Locating..."),
                  style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.2),
                ),
              ),
            ),



          // Floating Search Bar & Results Dropdown (only when NOT actively navigating and NOT in route selection mode)
          if (!navState.isNavigating && navState.activeRoute == null)
            Positioned(
              top: statusBarHeight + 16,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search Input Card
                  Card(
                    elevation: 4,
                    shadowColor: Colors.black.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: TextField(
                      key: const ValueKey('search_text_field'),
                      controller: _searchController,
                      onChanged: (val) {
                        ref.read(searchQueryProvider.notifier).state = val;
                      },
                      decoration: InputDecoration(
                        hintText: 'Search places or landmarks...',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 15),
                        prefixIcon: searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () {
                                  _searchController.clear();
                                  ref.read(searchQueryProvider.notifier).state = '';
                                  FocusScope.of(context).unfocus();
                                  setState(() {
                                    _selectedCategory = null;
                                    _onlineCategoryPlaces = [];
                                  });
                                },
                              )
                            : const Icon(Icons.search, color: Colors.grey),
                        suffixIcon: searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _searchController.clear();
                                  ref.read(searchQueryProvider.notifier).state = '';
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                  if (searchQuery.isEmpty) ...[
                    const SizedBox(height: 8),
                    _buildCategoryRow(),
                  ],

                  // Search Results list
                  if (searchQuery.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Card(
                      elevation: 6,
                      shadowColor: Colors.black.withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: searchResultsAsync.when(
                          data: (searchResults) {
                            if (searchResults.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, color: Colors.grey),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'No matching places found.',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return ListView.separated(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: searchResults.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final place = searchResults[index];
                                final isFavorite = favorites.any((fav) =>
                                    fav.name == place.name &&
                                    fav.latitude == place.latitude &&
                                    fav.longitude == place.longitude);

                                return ListTile(
                                  leading: Icon(
                                    isFavorite ? Icons.star : Icons.location_on,
                                    color: isFavorite ? Colors.amber : Colors.blue,
                                  ),
                                  title: Text(place.name),
                                  subtitle: Text(
                                    place.description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () {
                                    _mapController.move(
                                      LatLng(place.latitude, place.longitude),
                                      15.5,
                                    );
                                    _searchController.text = place.name;
                                    ref.read(searchQueryProvider.notifier).state = '';
                                    FocusScope.of(context).unfocus();
                                    setState(() {
                                      _selectedPlace = place;
                                      _selectedCategory = null;
                                      _onlineCategoryPlaces = [];
                                    });
                                  },
                                );
                              },
                            );
                          },
                          loading: () => const Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              ),
                            ),
                          ),
                          error: (err, stack) => Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: Colors.red),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Search failed. Please try again.',
                                    style: TextStyle(color: Colors.red.shade700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Auto-download overlay (modern progress toast)
          if (!navState.isNavigating && navState.activeRoute == null)
            Positioned(
              bottom: _selectedPlace != null ? 200 : 90,
              left: 0,
              right: 0,
              child: const AutoDownloadOverlay(),
            ),

          // Active Turn-by-Turn Instruction Panel
          if (navState.isNavigating && navState.activeRoute != null)
            Positioned(
              top: statusBarHeight + 16,
              left: 16,
              right: 16,
              child: Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        child: Icon(
                          _getTurnIcon(
                            navState.activeRoute!.steps.isNotEmpty &&
                                    navState.currentStepIndex < navState.activeRoute!.steps.length
                                ? navState.activeRoute!.steps[navState.currentStepIndex].instruction
                                : 'go straight',
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              navState.activeRoute!.steps.isNotEmpty &&
                                      navState.currentStepIndex < navState.activeRoute!.steps.length
                                  ? navState.activeRoute!.steps[navState.currentStepIndex].instruction
                                  : 'Follow the route',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            if (navState.activeRoute!.steps.isNotEmpty &&
                                navState.currentStepIndex < navState.activeRoute!.steps.length) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Next turn in ${(navState.activeRoute!.steps[navState.currentStepIndex].distance).toStringAsFixed(0)} m',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Destination Selection Details Card (Start Navigation)
          if (_selectedPlace != null && !navState.isNavigating && navState.activeRoute == null)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Builder(
                        builder: (context) {
                          final isFavorite = favorites.any((fav) =>
                              fav.name == _selectedPlace!.name &&
                              fav.latitude == _selectedPlace!.latitude &&
                              fav.longitude == _selectedPlace!.longitude);

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  _selectedPlace!.name,
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isFavorite)
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  tooltip: 'Delete Saved Place',
                                  onPressed: () async {
                                    final index = favorites.indexWhere((fav) =>
                                        fav.name == _selectedPlace!.name &&
                                        fav.latitude == _selectedPlace!.latitude &&
                                        fav.longitude == _selectedPlace!.longitude);
                                    if (index != -1) {
                                      await ref.read(favoritesProvider.notifier).removeFavorite(index);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('"${_selectedPlace!.name}" removed'),
                                          ),
                                        );
                                      }
                                      setState(() {
                                        _selectedPlace = null;
                                      });
                                    }
                                  },
                                ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  setState(() {
                                    _selectedPlace = null;
                                  });
                                },
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selectedPlace!.description,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[600],
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () async {
                                final userPos = location.value;
                                if (userPos == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Waiting for GPS signal to calculate route...'),
                                    ),
                                  );
                                  return;
                                }

                                final startLatLng = LatLng(userPos.latitude, userPos.longitude);
                                final endLatLng = LatLng(_selectedPlace!.latitude, _selectedPlace!.longitude);
                                
                                final name = _selectedPlace!.name;
                                
                                await ref.read(navigationProvider.notifier).calculateRoutes(
                                  start: startLatLng,
                                  end: endLatLng,
                                  destinationName: name,
                                );
                              },
                              icon: const Icon(Icons.navigation),
                              label: const Text('Start Navigation'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Active Guidance HUD (Distance, ETA, Stop button)
          if (navState.isNavigating)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (navState.isRerouting) ...[
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Recalculating route...',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  navState.formattedETA,
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${navState.formattedRemainingDistance} • Heading to ${navState.destinationName ?? "Destination"}',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Colors.grey[600],
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton.filledTonal(
                                style: IconButton.styleFrom(
                                  padding: const EdgeInsets.all(16),
                                ),
                                icon: const Icon(Icons.dashboard_customize_rounded),
                                tooltip: 'HUD Mode',
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const HudNavigationPage(),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              IconButton.filled(
                                style: IconButton.styleFrom(
                                  backgroundColor: Theme.of(context).colorScheme.error,
                                  foregroundColor: Theme.of(context).colorScheme.onError,
                                  padding: const EdgeInsets.all(16),
                                ),
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  ref.read(navigationProvider.notifier).stopNavigation();
                                },
                              ),
                            ],
                          ),

                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Route Selection & Preview Card (displays alternative routes and shortcuts)
          if (navState.activeRoute != null && !navState.isNavigating)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: Card(
                elevation: 10,
                shadowColor: Colors.black.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Select Route Option',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.route, size: 14, color: Colors.blue.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  _onlineCategoryPlaces.isNotEmpty || searchQuery.isNotEmpty ? "Online OSRM" : "Offline Dijkstra",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      // Horizontal list of route options
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: () {
                          final allRoutes = [
                            if (navState.activeRoute != null) navState.activeRoute!,
                            ...navState.alternativeRoutes
                          ];
                          double minDistance = double.infinity;
                          double minDuration = double.infinity;
                          for (final r in allRoutes) {
                            if (r.distance < minDistance) minDistance = r.distance;
                            if (r.duration < minDuration) minDuration = r.duration;
                          }

                          List<String> getRouteBadges(RouteInfo route) {
                            final List<String> b = [];
                            final bool isShortest = (route.distance - minDistance).abs() < 15.0; // within 15 meters
                            final bool isFastest = (route.duration - minDuration).abs() < 5.0;   // within 5 seconds
                            
                            if (isShortest && isFastest) {
                              b.add("Best Route");
                            } else {
                              if (isFastest) b.add("Fastest");
                              if (isShortest) b.add("Shortest");
                            }
                            
                            if (b.isEmpty) {
                              b.add("Alternative");
                            }
                            return b;
                          }

                          return Row(
                            children: [
                              // 1. Active Route Option
                              if (navState.activeRoute != null)
                                _buildRouteOptionCard(
                                  context,
                                  route: navState.activeRoute!,
                                  isActive: true,
                                  badges: getRouteBadges(navState.activeRoute!),
                                  onTap: () {}, // Already selected
                                ),
                              
                              // 2. Alternative Route Options
                              ...navState.alternativeRoutes.map((route) {
                                return Padding(
                                  padding: const EdgeInsets.only(left: 10),
                                  child: _buildRouteOptionCard(
                                    context,
                                    route: route,
                                    isActive: false,
                                    badges: getRouteBadges(route),
                                    onTap: () {
                                      ref.read(navigationProvider.notifier).selectAlternativeRoute(route);
                                    },
                                  ),
                                );
                              }),
                            ],
                          );
                        }(),
                      ),
                      
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {
                                ref.read(navigationProvider.notifier).stopNavigation();
                              },
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {
                                ref.read(navigationProvider.notifier).startGuidance();
                              },
                              icon: const Icon(Icons.navigation),
                              label: const Text('Start Guidance'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Dynamic Control Buttons Panel (Compass orientation and Center on User)
          Positioned(
            right: 16,
            bottom: () {
              if (navState.isNavigating) {
                return 130.0;
              } else if (navState.activeRoute != null) {
                return 280.0;
              } else if (_selectedPlace != null) {
                return 240.0;
              }
              return 24.0;
            }(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  heroTag: 'compassMode',
                  mini: true,
                  elevation: 6,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                  onPressed: _toggleOrientationMode,
                  tooltip: 'Map Orientation',
                  child: () {
                    switch (_orientationMode) {
                      case MapOrientationMode.northUp:
                        return const Icon(Icons.explore, size: 22);
                      case MapOrientationMode.headingUp:
                        return const Icon(Icons.navigation, size: 22);
                      case MapOrientationMode.navigation3D:
                        return const Icon(Icons.view_in_ar, size: 22);
                    }
                  }(),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'gpsCenter',
                  mini: true,
                  elevation: 6,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                  onPressed: _centerOnUser,
                  tooltip: 'Center on User',
                  child: const Icon(Icons.my_location, size: 22),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'tripRecord',
                  mini: true,
                  elevation: 6,
                  backgroundColor: recorderState.isRecording 
                      ? Colors.red[800] 
                      : Theme.of(context).colorScheme.primaryContainer,
                  foregroundColor: recorderState.isRecording 
                      ? Colors.white 
                      : Theme.of(context).colorScheme.onPrimaryContainer,
                  onPressed: _handleTripRecordingToggle,
                  tooltip: recorderState.isRecording ? 'Stop Recording' : 'Record Trip',
                  child: Icon(
                    recorderState.isRecording ? Icons.square : Icons.radio_button_checked,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
