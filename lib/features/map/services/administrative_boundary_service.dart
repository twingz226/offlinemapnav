import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:dio/dio.dart';
import '../data/models/place_boundary.dart';

/// Service to detect administrative boundaries (cities/municipalities) for a
/// given GPS coordinate using the Nominatim API.
///
/// Uses a two-step approach:
/// 1. Reverse-geocode the coordinate to find the city/municipality NAME.
/// 2. Search for that name to get the FULL administrative boundary bounding box,
///    ensuring all barangays and districts are included.
class AdministrativeBoundaryService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'User-Agent': 'OfflineNavigatorApp/1.0',
    },
  ));

  /// Reverse-geocode a single point and return the enclosing city/municipality
  /// as a [PlaceBoundary] with the FULL city boundary, or `null` if none could
  /// be determined.
  Future<PlaceBoundary?> getPlaceForLocation(double lat, double lng) async {
    try {
      // ── Step 1: Reverse-geocode to find the city name ──────────────
      final reverseResponse = await _dio.get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'lat': lat,
          'lon': lng,
          'format': 'jsonv2',
          'zoom': 10, // city-level detail
          'addressdetails': 1,
        },
      );

      if (reverseResponse.statusCode != 200 || reverseResponse.data == null) {
        return null;
      }

      final reverseData = reverseResponse.data;
      final address = reverseData['address'] as Map<String, dynamic>?;
      if (address == null) return null;

      // Extract city/municipality name in order of preference
      final cityName = address['city'] ??
          address['municipality'] ??
          address['town'] ??
          address['village'] ??
          address['county'];

      if (cityName == null) return null;

      // Extract country for a more precise search
      final country = address['country'] ?? '';
      final countryCode = address['country_code'] ?? '';

      debugPrint('🏙️ Step 1: Reverse-geocode detected city: $cityName');

      // ── Step 2: Search for the full city boundary ──────────────────
      // Respect Nominatim's 1 req/sec rate limit
      await Future.delayed(const Duration(milliseconds: 1100));

      final searchResponse = await _dio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'city': cityName,
          'country': country,
          'format': 'jsonv2',
          'limit': 5,
          'addressdetails': 1,
        },
      );

      LatLngBounds? fullBounds;
      String resolvedName = cityName.toString();

      if (searchResponse.statusCode == 200 && searchResponse.data is List) {
        final results = searchResponse.data as List;

        // Find the best match: prefer administrative boundary with matching
        // country code and the lowest place_rank (= largest admin area)
        Map<String, dynamic>? bestMatch;
        int bestRank = 999;

        for (final result in results) {
          final resultAddress = result['address'] as Map<String, dynamic>?;
          final resultCountryCode = resultAddress?['country_code'] ?? '';
          final resultType = result['type'] ?? '';
          final resultCategory = result['category'] ?? '';
          final resultRank = result['place_rank'] ?? 99;

          // Must match country
          if (countryCode.isNotEmpty && resultCountryCode != countryCode) {
            continue;
          }

          // Prefer administrative boundaries
          final isAdmin = resultCategory == 'boundary' && resultType == 'administrative';
          final isPlace = resultCategory == 'place';

          if ((isAdmin || isPlace) && resultRank < bestRank) {
            bestRank = resultRank;
            bestMatch = result;
          }
        }

        // Fall back to first result if no admin match found
        bestMatch ??= results.isNotEmpty ? results.first : null;

        if (bestMatch != null) {
          final bbox = bestMatch['boundingbox'] as List<dynamic>?;
          if (bbox != null && bbox.length == 4) {
            fullBounds = LatLngBounds(
              LatLng(
                double.parse(bbox[0].toString()),
                double.parse(bbox[2].toString()),
              ),
              LatLng(
                double.parse(bbox[1].toString()),
                double.parse(bbox[3].toString()),
              ),
            );
            resolvedName = bestMatch['name']?.toString() ?? resolvedName;
            debugPrint('🗺️ Step 2: Full boundary found for $resolvedName '
                '(rank=$bestRank, type=${bestMatch['type']}): '
                '${bbox[0]}–${bbox[1]}, ${bbox[2]}–${bbox[3]}');
          }
        }
      }

      // ── Fallback: use reverse-geocode bounding box if search failed ──
      if (fullBounds == null) {
        final bbox = reverseData['boundingbox'] as List<dynamic>?;
        if (bbox != null && bbox.length == 4) {
          fullBounds = LatLngBounds(
            LatLng(double.parse(bbox[0].toString()), double.parse(bbox[2].toString())),
            LatLng(double.parse(bbox[1].toString()), double.parse(bbox[3].toString())),
          );
          debugPrint('⚠️ Using reverse-geocode bbox as fallback for $resolvedName');
        } else {
          // Last resort: ~5km radius around the point
          fullBounds = LatLngBounds(
            LatLng(lat - 0.045, lng - 0.045),
            LatLng(lat + 0.045, lng + 0.045),
          );
          debugPrint('⚠️ Using ~5km radius fallback for $resolvedName');
        }
      }

      // Generate a stable ID from the city name
      final id = resolvedName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');

      return PlaceBoundary(
        id: id,
        name: resolvedName,
        bounds: fullBounds,
      );
    } catch (e) {
      debugPrint('AdministrativeBoundaryService error: $e');
    }
    return null;
  }

  /// Returns a list of [PlaceBoundary] objects visible in the given viewport.
  /// Samples the center point to detect the primary city.
  Future<List<PlaceBoundary>> getPlacesInBounds(LatLngBounds bounds) async {
    final centerLat = (bounds.north + bounds.south) / 2;
    final centerLng = (bounds.east + bounds.west) / 2;

    final centerPlace = await getPlaceForLocation(centerLat, centerLng);

    final places = <String, PlaceBoundary>{};
    if (centerPlace != null) {
      places[centerPlace.id] = centerPlace;
    }

    return places.values.toList();
  }
}
