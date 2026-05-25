import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'distance_service.dart';
import 'offline_routing_data.dart';

class RouteStep {
  final String instruction;
  final LatLng location;
  final double distance; // in meters
  final double duration; // in seconds

  RouteStep({
    required this.instruction,
    required this.location,
    required this.distance,
    required this.duration,
  });

  Map<String, dynamic> toJson() {
    return {
      'instruction': instruction,
      'lat': location.latitude,
      'lng': location.longitude,
      'distance': distance,
      'duration': duration,
    };
  }

  factory RouteStep.fromJson(Map<dynamic, dynamic> json) {
    return RouteStep(
      instruction: json['instruction'] as String,
      location: LatLng(json['lat'] as double, json['lng'] as double),
      distance: (json['distance'] as num).toDouble(),
      duration: (json['duration'] as num).toDouble(),
    );
  }
}

class RouteInfo {
  final List<LatLng> polyline;
  final double distance; // in meters
  final double duration; // in seconds
  final List<RouteStep> steps;

  RouteInfo({
    required this.polyline,
    required this.distance,
    required this.duration,
    required this.steps,
  });

  Map<String, dynamic> toJson() {
    return {
      'polyline': polyline.map((p) => [p.latitude, p.longitude]).toList(),
      'distance': distance,
      'duration': duration,
      'steps': steps.map((s) => s.toJson()).toList(),
    };
  }

  factory RouteInfo.fromJson(Map<dynamic, dynamic> json) {
    return RouteInfo(
      polyline: (json['polyline'] as List)
          .map((p) => LatLng((p as List)[0] as double, p[1] as double))
          .toList(),
      distance: (json['distance'] as num).toDouble(),
      duration: (json['duration'] as num).toDouble(),
      steps: (json['steps'] as List)
          .map((s) => RouteStep.fromJson(s as Map))
          .toList(),
    );
  }
}

class RoutingService {
  final _dio = Dio();

  Future<List<RouteInfo>> getRoutes({
    required LatLng start,
    required LatLng end,
    required bool isOnline,
  }) async {
    if (isOnline) {
      try {
        final url = 'https://router.project-osrm.org/route/v1/driving/'
            '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
            '?overview=full&geometries=geojson&steps=true&alternatives=true';
        
        debugPrint('RoutingService: Fetching routes from OSRM: $url');
        final response = await _dio.get(url);
        debugPrint('RoutingService: Response status code: ${response.statusCode}');
        if (response.statusCode == 200) {
          final data = response.data;
          if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
            final List<RouteInfo> routes = [];
            for (final routeData in data['routes']) {
              final geometry = routeData['geometry']['coordinates'] as List;
              final polyline = geometry.map((coord) => LatLng(coord[1] as double, coord[0] as double)).toList();
              
              final double distance = (routeData['distance'] as num).toDouble();
              final double duration = (routeData['duration'] as num).toDouble();
              
              final List<RouteStep> steps = [];
              final legs = routeData['legs'] as List;
              for (final leg in legs) {
                final legSteps = leg['steps'] as List;
                for (final step in legSteps) {
                  final maneuver = step['maneuver'];
                  final location = maneuver['location'] as List;
                  
                  String maneuverType = step['maneuver']['type'] ?? '';
                  String modifier = step['maneuver']['modifier'] ?? '';
                  String streetName = step['name'] ?? '';
                  
                  String instruction = '';
                  if (maneuverType == 'depart') {
                    instruction = 'Depart from starting point';
                  } else if (maneuverType == 'arrive') {
                    instruction = 'Arrive at destination';
                  } else {
                    String turnModifier = modifier.replaceAll('-', ' ');
                    String turnStr = maneuverType.contains('turn') ? maneuverType : 'turn $maneuverType';
                    instruction = '${turnStr.trim()} ${turnModifier.trim()} ${streetName.isNotEmpty ? 'on $streetName' : ''}';
                  }

                  steps.add(
                    RouteStep(
                      instruction: _cleanInstruction(instruction),
                      location: LatLng(location[1] as double, location[0] as double),
                      distance: (step['distance'] as num).toDouble(),
                      duration: (step['duration'] as num).toDouble(),
                    ),
                  );
                }
              }

              routes.add(RouteInfo(
                polyline: polyline,
                distance: distance,
                duration: duration,
                steps: steps,
              ));
            }

            // Save the primary route to cache
            if (routes.isNotEmpty) {
              _saveToCache(start, end, routes[0]);
            }

            return routes;
          }
        }
      } catch (e) {
        debugPrint('Online routing failed, falling back to offline: $e');
        if (e is DioException) {
          debugPrint('DioException: type=${e.type}, message=${e.message}, response=${e.response}');
        }
      }
    }

    // --- Offline Mode Fallbacks ---

    // 1. Check local offline route cache first (for any route generated previously)
    final cachedRoute = _checkCache(start, end);
    if (cachedRoute != null) {
      debugPrint('RoutingService: Serving route from offline cache');
      return [cachedRoute];
    }

    // 2. Check local Dumaguete road network graph Dijkstra routing
    final localGraphRoute = OfflineRoutingData.getOfflineRoute(start, end);
    if (localGraphRoute != null) {
      debugPrint('RoutingService: Serving route from local offline road graph');
      return [localGraphRoute];
    }

    // 3. Fallback to straight-line route if no graph matches (e.g. outside Dumaguete)
    debugPrint('RoutingService: Fallback to straight-line route');
    final polyline = [start, end];
    final distance = DistanceService.calculateDistance(start, end) * 1000; // convert to meters
    // Assume average speed of 40 km/h (11.1 m/s)
    final duration = distance / 11.1;

    final steps = [
      RouteStep(
        instruction: 'Head toward your destination',
        location: start,
        distance: distance,
        duration: duration,
      ),
      RouteStep(
        instruction: 'Arrive at destination',
        location: end,
        distance: 0,
        duration: 0,
      ),
    ];

    return [
      RouteInfo(
        polyline: polyline,
        distance: distance,
        duration: duration,
        steps: steps,
      )
    ];
  }

  String _cacheKey(LatLng start, LatLng end) {
    return '${start.latitude.toStringAsFixed(4)},${start.longitude.toStringAsFixed(4)}->${end.latitude.toStringAsFixed(4)},${end.longitude.toStringAsFixed(4)}';
  }

  void _saveToCache(LatLng start, LatLng end, RouteInfo route) {
    try {
      final box = Hive.box('routesCache');
      final key = _cacheKey(start, end);
      box.put(key, route.toJson());
      debugPrint('RoutingService: Successfully cached route under key: $key');
    } catch (e) {
      debugPrint('RoutingService: Failed to cache route: $e');
    }
  }

  RouteInfo? _checkCache(LatLng start, LatLng end) {
    try {
      final box = Hive.box('routesCache');
      print('RoutingService: Checking cache with ${box.length} entries. Start: $start, End: $end');
      if (box.isEmpty) {
        print('RoutingService: Cache box is empty.');
        return null;
      }

      for (final key in box.keys) {
        if (key is String) {
          final parts = key.split('->');
          if (parts.length == 2) {
            final startParts = parts[0].split(',');
            final endParts = parts[1].split(',');
            if (startParts.length == 2 && endParts.length == 2) {
              final cachedStartLat = double.tryParse(startParts[0]) ?? 0.0;
              final cachedStartLng = double.tryParse(startParts[1]) ?? 0.0;
              final cachedEndLat = double.tryParse(endParts[0]) ?? 0.0;
              final cachedEndLng = double.tryParse(endParts[1]) ?? 0.0;

              final double startDist = DistanceService.calculateDistance(
                start,
                LatLng(cachedStartLat, cachedStartLng),
              );
              final double endDist = DistanceService.calculateDistance(
                end,
                LatLng(cachedEndLat, cachedEndLng),
              );

              // If start and end are within ~100 meters (0.1 km) of cached points, reuse it
              if (startDist < 0.1 && endDist < 0.1) {
                final cachedData = box.get(key);
                if (cachedData is Map) {
                  debugPrint('RoutingService: Loaded cached route for key: $key');
                  return RouteInfo.fromJson(cachedData);
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('RoutingService: Error reading from cache: $e');
    }
    return null;
  }

  String _cleanInstruction(String instruction) {
    return instruction
        .replaceAll('  ', ' ')
        .replaceAll('turn turn', 'turn')
        .replaceAll('straight straight', 'go straight')
        .replaceAll('slight left', 'bear left')
        .replaceAll('slight right', 'bear right')
        .trim();
  }
}
