import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'distance_service.dart';
import 'offline_routing_data.dart';
import 'osm_graph_service.dart';
import '../presentation/providers/download_provider.dart';

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
  final List<double>? speedLimits; // speed limits in km/h

  RouteInfo({
    required this.polyline,
    required this.distance,
    required this.duration,
    required this.steps,
    this.speedLimits,
  });

  Map<String, dynamic> toJson() {
    return {
      'polyline': polyline.map((p) => [p.latitude, p.longitude]).toList(),
      'distance': distance,
      'duration': duration,
      'steps': steps.map((s) => s.toJson()).toList(),
      'speedLimits': speedLimits,
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
      speedLimits: (json['speedLimits'] as List?)
          ?.map((s) => (s as num).toDouble())
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
            '?overview=full&geometries=geojson&steps=true&alternatives=3';
        
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

            // Sort the routes by distance ascending so the shortest possible street route is always the primary route
            if (routes.isNotEmpty) {
              routes.sort((a, b) => a.distance.compareTo(b.distance));
              _saveToCache(start, end, routes);
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
    final cachedRoutes = _checkCache(start, end);
    if (cachedRoutes != null && cachedRoutes.isNotEmpty) {
      debugPrint('RoutingService: Serving routes from offline cache');
      return cachedRoutes;
    }

    // 2. Check compiled dynamic OSM graphs
    for (final region in availableRegions) {
      if (region.bounds.contains(start) && region.bounds.contains(end)) {
        try {
          final box = await Hive.openBox('osm_graphs');
          final nodesKey = '${region.id}_nodes';
          final edgesKey = '${region.id}_edges';
          if (box.containsKey(nodesKey) && box.containsKey(edgesKey)) {
            debugPrint('RoutingService: Found compiled offline graph for region: ${region.name}. Loading...');
            final List cachedNodesData = box.get(nodesKey) ?? [];
            final List cachedEdgesData = box.get(edgesKey) ?? [];

            final nodes = cachedNodesData.map((n) => OSMNode.fromJson(n as Map)).toList();
            final edges = cachedEdgesData.map((e) => OSMEdge.fromJson(e as Map)).toList();

            final dynamicRoutes = _findRouteOnDynamicGraph(start, end, nodes, edges);
            if (dynamicRoutes.isNotEmpty) {
              debugPrint('RoutingService: Successfully calculated path using dynamic offline OSM graph.');
              _saveToCache(start, end, dynamicRoutes);
              return dynamicRoutes;
            }
          }
        } catch (e) {
          debugPrint('RoutingService: Error solving on dynamic graph: $e');
        }
      }
    }

    // 3. Check local Dumaguete road network graph Dijkstra routing
    final localGraphRoutes = OfflineRoutingData.getOfflineRoutes(start, end);
    if (localGraphRoutes.isNotEmpty) {
      debugPrint('RoutingService: Serving routes from local offline road graph');
      _saveToCache(start, end, localGraphRoutes);
      return localGraphRoutes;
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

    final fallbackRoute = RouteInfo(
      polyline: polyline,
      distance: distance,
      duration: duration,
      steps: steps,
    );

    return [fallbackRoute];
  }

  String _cacheKey(LatLng start, LatLng end) {
    return '${start.latitude.toStringAsFixed(4)},${start.longitude.toStringAsFixed(4)}->${end.latitude.toStringAsFixed(4)},${end.longitude.toStringAsFixed(4)}';
  }

  void _saveToCache(LatLng start, LatLng end, List<RouteInfo> routes) {
    try {
      final box = Hive.box('routesCache');
      final key = _cacheKey(start, end);
      box.put(key, routes.map((r) => r.toJson()).toList());
      debugPrint('RoutingService: Successfully cached ${routes.length} routes under key: $key');
    } catch (e) {
      debugPrint('RoutingService: Failed to cache routes: $e');
    }
  }

  List<RouteInfo>? _checkCache(LatLng start, LatLng end) {
    try {
      final box = Hive.box('routesCache');
      debugPrint('RoutingService: Checking cache with ${box.length} entries. Start: $start, End: $end');
      if (box.isEmpty) {
        debugPrint('RoutingService: Cache box is empty.');
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
                if (cachedData is List) {
                  debugPrint('RoutingService: Loaded cached routes list for key: $key');
                  return cachedData.map((s) => RouteInfo.fromJson(s as Map)).toList();
                } else if (cachedData is Map) {
                  debugPrint('RoutingService: Loaded single cached route for key: $key');
                  return [RouteInfo.fromJson(cachedData)];
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

  List<RouteInfo> _findRouteOnDynamicGraph(
    LatLng start,
    LatLng end,
    List<OSMNode> nodes,
    List<OSMEdge> edges,
  ) {
    OSMNode? nearestStart;
    OSMNode? nearestEnd;
    double minStartDist = double.infinity;
    double minEndDist = double.infinity;

    for (final node in nodes) {
      final dStart = DistanceService.calculateDistance(start, node.position);
      final dEnd = DistanceService.calculateDistance(end, node.position);

      if (dStart < minStartDist) {
        minStartDist = dStart;
        nearestStart = node;
      }
      if (dEnd < minEndDist) {
        minEndDist = dEnd;
        nearestEnd = node;
      }
    }

    if (nearestStart == null || nearestEnd == null || minStartDist > 15.0 || minEndDist > 15.0) {
      debugPrint('RoutingService: Snapped coordinates are too far from dynamic OSM graph region.');
      return [];
    }

    final path = _dynamicAStar(nearestStart.id, nearestEnd.id, nodes, edges);
    if (path.isEmpty && nearestStart.id != nearestEnd.id) {
      return [];
    }

    final routes = <RouteInfo>[];
    final primaryRoute = _buildDynamicRouteInfo(start, end, nearestStart, nearestEnd, minStartDist, path);
    if (primaryRoute != null) {
      routes.add(primaryRoute);
    }

    // Alternative route (blocking the primary path's main edge)
    if (path.isNotEmpty) {
      final Set<String> primaryEdgeIds = path.map((e) => e.id).toSet();
      final altPath = _dynamicAStar(nearestStart.id, nearestEnd.id, nodes, edges, blockedEdgeIds: primaryEdgeIds);
      if (altPath.isNotEmpty) {
        final altRoute = _buildDynamicRouteInfo(start, end, nearestStart, nearestEnd, minStartDist, altPath);
        if (altRoute != null) {
          routes.add(altRoute);
        }
      }
    }

    return routes;
  }

  List<OSMEdge> _dynamicAStar(
    String startId,
    String endId,
    List<OSMNode> nodes,
    List<OSMEdge> edges, {
    Set<String> blockedEdgeIds = const {},
  }) {
    final Map<String, LatLng> nodePositions = {
      for (final n in nodes) n.id: n.position
    };

    double heuristic(String id) {
      final pos = nodePositions[id];
      final endPos = nodePositions[endId];
      if (pos == null || endPos == null) return 0.0;
      return DistanceService.calculateDistance(pos, endPos) * 1000.0;
    }

    final Map<String, double> gScore = {
      for (final n in nodes) n.id: double.infinity
    };
    gScore[startId] = 0.0;

    final Map<String, double> fScore = {
      for (final n in nodes) n.id: double.infinity
    };
    fScore[startId] = heuristic(startId);

    final Set<String> openSet = {startId};
    final Map<String, OSMEdge?> previousEdges = {};

    while (openSet.isNotEmpty) {
      String? currentId;
      double minF = double.infinity;
      for (final id in openSet) {
        if (fScore[id]! < minF) {
          minF = fScore[id]!;
          currentId = id;
        }
      }

      if (currentId == null || currentId == endId) {
        break;
      }

      openSet.remove(currentId);

      final neighbors = edges.where((e) =>
          (e.sourceId == currentId || e.targetId == currentId) &&
          !blockedEdgeIds.contains(e.id));

      for (final edge in neighbors) {
        final neighborId = edge.sourceId == currentId ? edge.targetId : edge.sourceId;
        final tentativeGScore = gScore[currentId]! + edge.distance;

        if (tentativeGScore < gScore[neighborId]!) {
          previousEdges[neighborId] = edge;
          gScore[neighborId] = tentativeGScore;
          fScore[neighborId] = tentativeGScore + heuristic(neighborId);
          openSet.add(neighborId);
        }
      }
    }

    if (gScore[endId] == double.infinity) {
      return [];
    }

    final List<OSMEdge> path = [];
    String current = endId;
    while (current != startId) {
      final edge = previousEdges[current];
      if (edge == null) break;
      path.insert(0, edge);
      current = edge.sourceId == current ? edge.targetId : edge.sourceId;
    }

    return path;
  }

  RouteInfo? _buildDynamicRouteInfo(
    LatLng start,
    LatLng end,
    OSMNode nearestStart,
    OSMNode nearestEnd,
    double minStartDist,
    List<OSMEdge> path,
  ) {
    final List<LatLng> fullPolyline = [];
    fullPolyline.add(start);

    final List<double> speedLimits = [];
    speedLimits.add(40.0); // Start segment default limit

    final List<RouteStep> steps = [];
    double totalDistance = 0.0;

    totalDistance += minStartDist * 1000;
    steps.add(
      RouteStep(
        instruction: 'Head toward ${nearestStart.name}',
        location: start,
        distance: minStartDist * 1000,
        duration: (minStartDist * 1000) / 10.0,
      ),
    );

    String currentId = nearestStart.id;
    String currentStreet = '';

    for (final edge in path) {
      List<LatLng> edgePoints;
      if (edge.targetId == currentId) {
        edgePoints = edge.polyline.reversed.toList();
        currentId = edge.sourceId;
      } else {
        edgePoints = edge.polyline.toList();
        currentId = edge.targetId;
      }

      if (fullPolyline.isNotEmpty && edgePoints.isNotEmpty) {
        if (fullPolyline.last == edgePoints.first) {
          edgePoints.removeAt(0);
        }
      }
      fullPolyline.addAll(edgePoints);
      totalDistance += edge.distance;

      // Add speed limits for each segment in this edge
      for (int j = 0; j < edgePoints.length - 1; j++) {
        speedLimits.add(edge.speedLimit);
      }

      if (edge.streetName != currentStreet) {
        currentStreet = edge.streetName;
        steps.add(
          RouteStep(
            instruction: 'Turn onto ${edge.streetName}',
            location: edgePoints.isNotEmpty ? edgePoints.first : edge.polyline.first,
            distance: edge.distance,
            duration: edge.distance / 10.0,
          ),
        );
      } else if (steps.isNotEmpty) {
        final lastIdx = steps.length - 1;
        steps[lastIdx] = RouteStep(
          instruction: steps[lastIdx].instruction,
          location: steps[lastIdx].location,
          distance: steps[lastIdx].distance + edge.distance,
          duration: steps[lastIdx].duration + (edge.distance / 10.0),
        );
      }
    }

    if (fullPolyline.last != end) {
      fullPolyline.add(end);
      speedLimits.add(40.0); // End segment default limit
    }

    final finalDist = DistanceService.calculateDistance(nearestEnd.position, end) * 1000;
    totalDistance += finalDist;

    steps.add(
      RouteStep(
        instruction: 'Arrive at destination',
        location: nearestEnd.position,
        distance: finalDist,
        duration: finalDist / 10.0,
      ),
    );

    final double totalDuration = totalDistance / 10.0;

    return RouteInfo(
      polyline: fullPolyline,
      distance: totalDistance,
      duration: totalDuration,
      steps: steps,
      speedLimits: speedLimits,
    );
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
