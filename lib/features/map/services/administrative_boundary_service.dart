import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../data/models/place_boundary.dart';

/// Service to fetch administrative boundaries (cities/municipalities) within a viewport.
/// Currently uses a static in‑memory list of sample places for demo purposes.
class AdministrativeBoundaryService {
  // Sample place data – replace with real lookup (e.g., GeoJSON, Overpass) later.
  static final List<PlaceBoundary> _samplePlaces = [
    PlaceBoundary(
      id: 'dumaguete_city',
      name: 'Dumaguete City',
      bounds: LatLngBounds(
        LatLng(9.05, 123.5), // south‑west corner
        LatLng(9.1, 123.6),   // north‑east corner
      ),
    ),
    PlaceBoundary(
      id: 'sibulan',
      name: 'Sibulan',
      bounds: LatLngBounds(
        LatLng(9.0, 123.45),
        LatLng(9.03, 123.5),
      ),
    ),
  ];

  /// Returns a list of [PlaceBoundary] objects that intersect the given [bounds].
  Future<List<PlaceBoundary>> getPlacesInBounds(LatLngBounds bounds) async {
    bool _intersects(LatLngBounds a, LatLngBounds b) {
      return !(a.west > b.east || a.east < b.west || a.south > b.north || a.north < b.south);
    }

    return _samplePlaces.where((place) => _intersects(place.bounds, bounds)).toList();
  }
}
