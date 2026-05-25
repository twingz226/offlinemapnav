import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../data/models/favorite_place_model.dart';
import 'favorites_provider.dart';
import 'network_provider.dart';
import 'location_provider.dart';

// Pre-defined offline points of interest (POIs) in the Dumaguete region
final builtinPlaces = [
  FavoritePlaceModel(
    name: 'Silliman University',
    latitude: 9.3120,
    longitude: 123.3075,
    description: 'Historic private research university in Dumaguete.',
  ),
  FavoritePlaceModel(
    name: 'Dumaguete Belfry',
    latitude: 9.3072,
    longitude: 123.3086,
    description: 'Historic stone bell tower built in 1811.',
  ),
  FavoritePlaceModel(
    name: 'Rizal Boulevard',
    latitude: 9.3088,
    longitude: 123.3106,
    description: 'Scenic waterfront promenade named after Dr. Jose Rizal.',
  ),
  FavoritePlaceModel(
    name: 'Robinsons Place Dumaguete',
    latitude: 9.2942,
    longitude: 123.3005,
    description: 'Major shopping mall in Dumaguete City.',
  ),
  FavoritePlaceModel(
    name: 'Dumaguete Port',
    latitude: 9.3117,
    longitude: 123.3128,
    description: 'Seaport connecting Dumaguete to Cebu and other islands.',
  ),
  FavoritePlaceModel(
    name: 'Quezon Park',
    latitude: 9.3075,
    longitude: 123.3082,
    description: 'Public park situated near the belfry and cathedral.',
  ),
  FavoritePlaceModel(
    name: 'Valencia Town Plaza',
    latitude: 9.2818,
    longitude: 123.2458,
    description: 'Cool municipal plaza nestled in the foothills of Mt. Talinis.',
  ),
  FavoritePlaceModel(
    name: 'Casaroro Falls',
    latitude: 9.2811,
    longitude: 123.2081,
    description: 'Breathtaking single-column waterfall nestled in Valencia forest.',
  ),
  FavoritePlaceModel(
    name: 'Pulangbato Falls',
    latitude: 9.3069,
    longitude: 123.2039,
    description: 'Popular red-rock waterfall with natural swimming pools in Valencia.',
  ),
  FavoritePlaceModel(
    name: 'Tejero Highland Resort and Waterpark',
    latitude: 9.2906,
    longitude: 123.2389,
    description: 'Resort with outdoor natural spring pools and water slides.',
  ),
  FavoritePlaceModel(
    name: 'Forest Camp Riverside Resort',
    latitude: 9.2831,
    longitude: 123.2458,
    description: 'Mountain resort featuring cold spring pools, zip lines, and campsites.',
  ),
  FavoritePlaceModel(
    name: 'Dauin Beach & Marine Sanctuaries',
    latitude: 9.1895,
    longitude: 123.2646,
    description: 'Beautiful sandy beach and world-renowned coral reef diving resorts.',
  ),
  FavoritePlaceModel(
    name: 'Apo Island Beach & Dive Resort',
    latitude: 9.0792,
    longitude: 123.2711,
    description: 'Famous beach resort and marine sanctuary for swimming with sea turtles.',
  ),
  FavoritePlaceModel(
    name: 'Tierra Alta Resort & Pool',
    latitude: 9.2974,
    longitude: 123.2566,
    description: 'Luxury hillside resort featuring a iconic lighthouse and infinity pool.',
  ),
  FavoritePlaceModel(
    name: 'Manjuyod Sandbar Beach',
    latitude: 9.6153,
    longitude: 123.1557,
    description: 'Stunning white sandbar and cottages often called the Maldives of the Philippines.',
  ),
];

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider.autoDispose<List<FavoritePlaceModel>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) {
    return [];
  }

  // 1. Debounce query for 500ms to avoid spamming network queries
  await Future.delayed(const Duration(milliseconds: 500));
  if (ref.read(searchQueryProvider) != query) {
    throw Exception('Query changed');
  }

  final favorites = ref.watch(favoritesProvider);
  final isOnlineAsync = ref.watch(connectivityProvider);
  final isOnline = isOnlineAsync.value ?? false;
  final locationAsync = ref.watch(locationProvider);
  final userLocation = locationAsync.value;

  if (isOnline) {
    try {
      final dio = Dio();
      dio.options.headers['User-Agent'] = 'OfflineNavigatorApp/1.0.0';
      dio.options.connectTimeout = const Duration(seconds: 5);
      dio.options.receiveTimeout = const Duration(seconds: 5);

      final queryParams = {
        'q': query,
        'format': 'json',
        'limit': 10,
        'addressdetails': 1,
      };

      if (userLocation != null) {
        queryParams['lat'] = userLocation.latitude.toString();
        queryParams['lon'] = userLocation.longitude.toString();
      }

      final response = await dio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200 && response.data is List) {
        final List results = response.data;
        return results.map((item) {
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
      }
    } catch (e) {
      // Log error and fall back to local offline search
      debugPrint('Online geocoding search error: $e');
    }
  }

  // Offline / local search fallback
  final allPlaces = [
    ...favorites,
    ...builtinPlaces,
  ];

  final uniquePlaces = <String, FavoritePlaceModel>{};
  for (final p in allPlaces) {
    uniquePlaces['${p.name}_${p.latitude.toStringAsFixed(4)}_${p.longitude.toStringAsFixed(4)}'] = p;
  }

  return uniquePlaces.values.where((place) {
    final nameMatch = place.name.toLowerCase().contains(query.toLowerCase());
    final descMatch = place.description.toLowerCase().contains(query.toLowerCase());
    return nameMatch || descMatch;
  }).toList();
});


