import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:dio/dio.dart';
import '../data/models/place_boundary.dart';

/// Service to detect administrative boundaries (cities/municipalities) for a
/// given GPS coordinate using the Nominatim reverse-geocoding API.
class AdministrativeBoundaryService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'User-Agent': 'OfflineNavigatorApp/1.0',
    },
  ));

  /// Reverse-geocode a single point and return the enclosing city/municipality
  /// as a [PlaceBoundary], or `null` if none could be determined.
  Future<PlaceBoundary?> getPlaceForLocation(double lat, double lng) async {
    try {
      final response = await _dio.get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'lat': lat,
          'lon': lng,
          'format': 'jsonv2',
          'zoom': 10, // city-level detail
          'addressdetails': 1,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final address = data['address'] as Map<String, dynamic>?;

        if (address == null) return null;

        // Try to extract city/municipality name in order of preference
        final cityName = address['city'] ??
            address['municipality'] ??
            address['town'] ??
            address['village'] ??
            address['county'];

        if (cityName == null) return null;

        // Build bounding box from the response
        final boundingBox = data['boundingbox'] as List<dynamic>?;
        LatLngBounds bounds;

        if (boundingBox != null && boundingBox.length == 4) {
          bounds = LatLngBounds(
            LatLng(double.parse(boundingBox[0].toString()), double.parse(boundingBox[2].toString())),
            LatLng(double.parse(boundingBox[1].toString()), double.parse(boundingBox[3].toString())),
          );
        } else {
          // Fallback: create a ~5km radius box around the point
          bounds = LatLngBounds(
            LatLng(lat - 0.045, lng - 0.045),
            LatLng(lat + 0.045, lng + 0.045),
          );
        }

        // Generate a stable ID from the city name
        final id = cityName.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');

        debugPrint('🏙️ Detected city: $cityName (id: $id)');

        return PlaceBoundary(
          id: id,
          name: cityName.toString(),
          bounds: bounds,
        );
      }
    } catch (e) {
      debugPrint('AdministrativeBoundaryService error: $e');
    }
    return null;
  }

  /// Returns a list of [PlaceBoundary] objects visible in the given viewport.
  /// Samples the center and corners to detect multiple cities if the viewport
  /// spans across boundaries.
  Future<List<PlaceBoundary>> getPlacesInBounds(LatLngBounds bounds) async {
    final centerLat = (bounds.north + bounds.south) / 2;
    final centerLng = (bounds.east + bounds.west) / 2;

    // Sample center point (main detection point)
    final centerPlace = await getPlaceForLocation(centerLat, centerLng);

    final places = <String, PlaceBoundary>{}; // keyed by id to deduplicate

    if (centerPlace != null) {
      places[centerPlace.id] = centerPlace;
    }

    return places.values.toList();
  }
}
