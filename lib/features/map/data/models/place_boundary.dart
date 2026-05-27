import 'package:flutter_map/flutter_map.dart';

/// Represents an administrative area (city/municipality) with a bounding box.
class PlaceBoundary {
  final String id; // unique identifier, e.g., "dumaguete_city"
  final String name; // human‑readable name
  final LatLngBounds bounds; // geographic bounding box

  const PlaceBoundary({
    required this.id,
    required this.name,
    required this.bounds,
  });
}
