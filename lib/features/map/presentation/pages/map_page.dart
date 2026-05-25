import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../widgets/map_view.dart';
import '../widgets/auto_download_overlay.dart';
import '../providers/location_provider.dart';
import '../providers/auto_download_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/search_provider.dart';
import '../providers/navigation_provider.dart';
import '../../data/models/favorite_place_model.dart';

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});

  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> {
  late final MapController _mapController;
  late final TextEditingController _searchController;
  FavoritePlaceModel? _selectedPlace;
  String? _selectedCategory;
  List<FavoritePlaceModel> _onlineCategoryPlaces = [];
  bool _isLoadingCategoryPlaces = false;
  LatLng? _currentMapCenter;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

    final allPlaces = [
      ...ref.read(favoritesProvider),
      ...builtinPlaces,
      ..._onlineCategoryPlaces,
    ];

    final uniquePlaces = <String, FavoritePlaceModel>{};
    for (final p in allPlaces) {
      uniquePlaces['${p.name.trim()}_${p.latitude.toStringAsFixed(4)}_${p.longitude.toStringAsFixed(4)}'] = p;
    }

    final query = _selectedCategory!.toLowerCase();
    return uniquePlaces.values.where((place) {
      final name = place.name.toLowerCase();
      final desc = place.description.toLowerCase();

      if (query == 'beaches') {
        return name.contains('beach') || desc.contains('beach') || name.contains('sandbar') || desc.contains('sandbar');
      } else if (query == 'falls') {
        return name.contains('falls') || desc.contains('falls') || name.contains('waterfall') || desc.contains('waterfall');
      } else if (query == 'pools') {
        return name.contains('pool') || desc.contains('pool') || name.contains('waterpark') || desc.contains('waterpark');
      } else if (query == 'springs') {
        return name.contains('spring') || desc.contains('spring');
      } else if (query == 'camps') {
        return name.contains('camp') || desc.contains('camp');
      }
      return false;
    }).toList();
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

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(locationProvider);
    final favorites = ref.watch(favoritesProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final searchResultsAsync = ref.watch(searchResultsProvider);
    final navState = ref.watch(navigationProvider);

    // Auto center on user location when it first loads successfully or when navigating
    ref.listen<AsyncValue<Position?>>(locationProvider, (previous, next) {
      next.whenOrNull(
        data: (pos) {
          if (pos != null) {
            final activeNav = ref.read(navigationProvider);
            if (activeNav.isNavigating) {
              _mapController.move(LatLng(pos.latitude, pos.longitude), 16.5);
            } else if (previous == null || previous.value == null) {
              _mapController.move(LatLng(pos.latitude, pos.longitude), 15.0);
            }
          }
        },
      );
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
            userPosition: location.value,
            mapController: _mapController,
            routePolyline: navState.activeRoute?.polyline,
            alternativePolylines: navState.alternativeRoutes.map((r) => r.polyline).toList(),
            isNavigating: navState.isNavigating,
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



          // Floating Search Bar & Results Dropdown (only when NOT actively navigating)
          if (!navState.isNavigating)
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
          if (!navState.isNavigating)
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
          if (_selectedPlace != null && !navState.isNavigating)
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
                                setState(() {
                                  _selectedPlace = null;
                                });
                                
                                await ref.read(navigationProvider.notifier).startNavigation(
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
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                navState.formattedETA,
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${navState.formattedRemainingDistance} • Heading to ${navState.destinationName ?? "Destination"}',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                              ),
                            ],
                          ),
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
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: navState.isNavigating
          ? null
          : FloatingActionButton(
              heroTag: 'gps',
              onPressed: _centerOnUser,
              child: const Icon(Icons.my_location),
            ),
    );
  }
}
