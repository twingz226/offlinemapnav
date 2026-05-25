import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../data/models/favorite_place_model.dart';
import '../../services/poi_service.dart';
import '../../../../core/utils/fuzzy_matcher.dart';
import 'favorites_provider.dart';
import 'network_provider.dart';
import 'location_provider.dart';

// Maintain global reference for backward compatibility with map_page.dart
final builtinPlaces = POIService.builtinPlaces;

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

  // Offline / local search fallback using Fuzzy Matcher
  final allPlaces = [
    ...favorites,
    ...builtinPlaces,
  ];

  final uniquePlaces = <String, FavoritePlaceModel>{};
  for (final p in allPlaces) {
    uniquePlaces['${p.name}_${p.latitude.toStringAsFixed(4)}_${p.longitude.toStringAsFixed(4)}'] = p;
  }

  // Calculate similarity scores for all offline places
  final scoredPlaces = uniquePlaces.values.map((place) {
    final nameScore = FuzzyMatcher.getCombinedSimilarity(query, place.name);
    final descScore = FuzzyMatcher.getCombinedSimilarity(query, place.description);
    
    // Weighted score: 70% name match, 30% description match
    final double score = (nameScore * 0.7) + (descScore * 0.3);
    
    return _ScoredPlace(place: place, score: score);
  }).where((item) => item.score > 0.18).toList(); // threshold for relevance

  // Sort by highest similarity score
  scoredPlaces.sort((a, b) => b.score.compareTo(a.score));

  return scoredPlaces.map((item) => item.place).toList();
});

class _ScoredPlace {
  final FavoritePlaceModel place;
  final double score;

  _ScoredPlace({
    required this.place,
    required this.score,
  });
}



