import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';
import 'distance_service.dart';
import 'routing_service.dart';

class GraphNode {
  final String id;
  final String name;
  final LatLng position;

  GraphNode({
    required this.id,
    required this.name,
    required this.position,
  });
}

class GraphEdge {
  final String id;
  final String sourceId;
  final String targetId;
  final String streetName;
  final List<LatLng> polyline;
  final double distance; // in meters

  GraphEdge({
    required this.id,
    required this.sourceId,
    required this.targetId,
    required this.streetName,
    required this.polyline,
    required this.distance,
  });
}

class OfflineRoutingData {
  static final List<GraphNode> nodes = [
    GraphNode(id: 'belfry', name: 'Dumaguete Belfry', position: LatLng(9.3063, 123.3082)),
    GraphNode(id: 'silliman_gate', name: 'Silliman University Main Gate', position: LatLng(9.3130, 123.3065)),
    GraphNode(id: 'airport_junc', name: 'Dumaguete Airport Junction', position: LatLng(9.3332, 123.3013)),
    GraphNode(id: 'sibulan_port', name: 'Sibulan Port', position: LatLng(9.3582, 123.3444)),
    GraphNode(id: 'robinsons', name: 'Robinsons Place Dumaguete', position: LatLng(9.2963, 123.3006)),
    GraphNode(id: 'bacong', name: 'Bacong Crossing', position: LatLng(9.2483, 123.2950)),
    GraphNode(id: 'valencia_junc', name: 'Valencia Crossing', position: LatLng(9.2804, 123.2458)),
    GraphNode(id: 'valencia_plaza', name: 'Valencia Plaza', position: LatLng(9.2810, 123.2450)),
    GraphNode(id: 'real_silliman', name: 'Real St & Silliman Ave Junction', position: LatLng(9.3081, 123.3060)),
    GraphNode(id: 'boulevard', name: 'Rizal Boulevard Beachfront', position: LatLng(9.3075, 123.3115)),
    
    // Small Streets / Secondary Junctions
    GraphNode(id: 'perdices_silliman', name: 'Perdices St & Silliman Ave', position: LatLng(9.3098, 123.3093)),
    GraphNode(id: 'perdices_colon', name: 'Perdices St & Colon St', position: LatLng(9.3060, 123.3097)),
    GraphNode(id: 'locsin_silliman', name: 'Locsin St & Silliman Ave', position: LatLng(9.3090, 123.3076)),
    GraphNode(id: 'locsin_colon', name: 'Locsin St & Colon St', position: LatLng(9.3053, 123.3080)),
    GraphNode(id: 'cervantes_real', name: 'Real St & Cervantes St', position: LatLng(9.3035, 123.3055)),
    GraphNode(id: 'cervantes_locsin', name: 'Locsin St & Cervantes St', position: LatLng(9.3030, 123.3068)),
  ];

  static final List<GraphEdge> edges = [
    GraphEdge(
      id: 'bacong_robinsons',
      sourceId: 'bacong',
      targetId: 'robinsons',
      streetName: 'Dumaguete-South Road',
      distance: 5400.0,
      polyline: [
        LatLng(9.2483, 123.2950),
        LatLng(9.2550, 123.2960),
        LatLng(9.2620, 123.2970),
        LatLng(9.2700, 123.2980),
        LatLng(9.2800, 123.2990),
        LatLng(9.2900, 123.3000),
        LatLng(9.2963, 123.3006),
      ],
    ),
    GraphEdge(
      id: 'robinsons_cervantes',
      sourceId: 'robinsons',
      targetId: 'cervantes_real',
      streetName: 'Real Street',
      distance: 950.0,
      polyline: [
        LatLng(9.2963, 123.3006),
        LatLng(9.2980, 123.3015),
        LatLng(9.3010, 123.3035),
        LatLng(9.3035, 123.3055),
      ],
    ),
    GraphEdge(
      id: 'cervantes_belfry',
      sourceId: 'cervantes_real',
      targetId: 'belfry',
      streetName: 'Real Street',
      distance: 450.0,
      polyline: [
        LatLng(9.3035, 123.3055),
        LatLng(9.3040, 123.3060),
        LatLng(9.3063, 123.3082),
      ],
    ),
    GraphEdge(
      id: 'belfry_real_silliman',
      sourceId: 'belfry',
      targetId: 'real_silliman',
      streetName: 'Real Street',
      distance: 300.0,
      polyline: [
        LatLng(9.3063, 123.3082),
        LatLng(9.3072, 123.3071),
        LatLng(9.3081, 123.3060),
      ],
    ),
    GraphEdge(
      id: 'real_silliman_gate',
      sourceId: 'real_silliman',
      targetId: 'silliman_gate',
      streetName: 'North National Highway',
      distance: 550.0,
      polyline: [
        LatLng(9.3081, 123.3060),
        LatLng(9.3105, 123.3062),
        LatLng(9.3130, 123.3065),
      ],
    ),
    GraphEdge(
      id: 'silliman_gate_airport',
      sourceId: 'silliman_gate',
      targetId: 'airport_junc',
      streetName: 'North National Highway',
      distance: 2300.0,
      polyline: [
        LatLng(9.3130, 123.3065),
        LatLng(9.3180, 123.3050),
        LatLng(9.3240, 123.3035),
        LatLng(9.3290, 123.3020),
        LatLng(9.3332, 123.3013),
      ],
    ),
    GraphEdge(
      id: 'airport_sibulan',
      sourceId: 'airport_junc',
      targetId: 'sibulan_port',
      streetName: 'North National Highway',
      distance: 5600.0,
      polyline: [
        LatLng(9.3332, 123.3013),
        LatLng(9.3370, 123.3050),
        LatLng(9.3410, 123.3110),
        LatLng(9.3460, 123.3180),
        LatLng(9.3500, 123.3260),
        LatLng(9.3540, 123.3350),
        LatLng(9.3582, 123.3444),
      ],
    ),
    GraphEdge(
      id: 'robinsons_valencia_junc',
      sourceId: 'robinsons',
      targetId: 'valencia_junc',
      streetName: 'Dumaguete-Valencia Road',
      distance: 6300.0,
      polyline: [
        LatLng(9.2963, 123.3006),
        LatLng(9.2930, 123.2850),
        LatLng(9.2890, 123.2700),
        LatLng(9.2840, 123.2550),
        LatLng(9.2804, 123.2458),
      ],
    ),
    GraphEdge(
      id: 'valencia_junc_plaza',
      sourceId: 'valencia_junc',
      targetId: 'valencia_plaza',
      streetName: 'Valencia Road',
      distance: 120.0,
      polyline: [
        LatLng(9.2804, 123.2458),
        LatLng(9.2810, 123.2450),
      ],
    ),
    GraphEdge(
      id: 'real_silliman_locsin',
      sourceId: 'real_silliman',
      targetId: 'locsin_silliman',
      streetName: 'Silliman Avenue',
      distance: 180.0,
      polyline: [
        LatLng(9.3081, 123.3060),
        LatLng(9.3090, 123.3076),
      ],
    ),
    GraphEdge(
      id: 'locsin_perdices_silliman',
      sourceId: 'locsin_silliman',
      targetId: 'perdices_silliman',
      streetName: 'Silliman Avenue',
      distance: 200.0,
      polyline: [
        LatLng(9.3090, 123.3076),
        LatLng(9.3098, 123.3093),
      ],
    ),
    GraphEdge(
      id: 'perdices_silliman_boulevard',
      sourceId: 'perdices_silliman',
      targetId: 'boulevard',
      streetName: 'Silliman Avenue',
      distance: 250.0,
      polyline: [
        LatLng(9.3098, 123.3093),
        LatLng(9.3075, 123.3115),
      ],
    ),
    GraphEdge(
      id: 'boulevard_silliman_gate',
      sourceId: 'boulevard',
      targetId: 'silliman_gate',
      streetName: 'Rizal Boulevard',
      distance: 800.0,
      polyline: [
        LatLng(9.3075, 123.3115),
        LatLng(9.3100, 123.3105),
        LatLng(9.3120, 123.3085),
        LatLng(9.3130, 123.3065),
      ],
    ),
    GraphEdge(
      id: 'boulevard_belfry',
      sourceId: 'boulevard',
      targetId: 'belfry',
      streetName: 'Silliman Avenue & Boulevard Link',
      distance: 400.0,
      polyline: [
        LatLng(9.3075, 123.3115),
        LatLng(9.3070, 123.3095),
        LatLng(9.3063, 123.3082),
      ],
    ),
    
    // Small Street Segments (Locsin, Perdices, Colon, Cervantes)
    GraphEdge(
      id: 'belfry_locsin_colon',
      sourceId: 'belfry',
      targetId: 'locsin_colon',
      streetName: 'Colon Street',
      distance: 150.0,
      polyline: [
        LatLng(9.3063, 123.3082),
        LatLng(9.3053, 123.3080),
      ],
    ),
    GraphEdge(
      id: 'locsin_perdices_colon',
      sourceId: 'locsin_colon',
      targetId: 'perdices_colon',
      streetName: 'Colon Street',
      distance: 200.0,
      polyline: [
        LatLng(9.3053, 123.3080),
        LatLng(9.3060, 123.3097),
      ],
    ),
    GraphEdge(
      id: 'perdices_colon_boulevard',
      sourceId: 'perdices_colon',
      targetId: 'boulevard',
      streetName: 'Colon Street',
      distance: 220.0,
      polyline: [
        LatLng(9.3060, 123.3097),
        LatLng(9.3075, 123.3115),
      ],
    ),
    GraphEdge(
      id: 'locsin_silliman_colon',
      sourceId: 'locsin_silliman',
      targetId: 'locsin_colon',
      streetName: 'Locsin Street',
      distance: 410.0,
      polyline: [
        LatLng(9.3090, 123.3076),
        LatLng(9.3053, 123.3080),
      ],
    ),
    GraphEdge(
      id: 'perdices_silliman_colon',
      sourceId: 'perdices_silliman',
      targetId: 'perdices_colon',
      streetName: 'Perdices Street',
      distance: 420.0,
      polyline: [
        LatLng(9.3098, 123.3093),
        LatLng(9.3060, 123.3097),
      ],
    ),
    GraphEdge(
      id: 'cervantes_real_locsin',
      sourceId: 'cervantes_real',
      targetId: 'cervantes_locsin',
      streetName: 'Cervantes Street',
      distance: 160.0,
      polyline: [
        LatLng(9.3035, 123.3055),
        LatLng(9.3030, 123.3068),
      ],
    ),
    GraphEdge(
      id: 'cervantes_locsin_colon',
      sourceId: 'cervantes_locsin',
      targetId: 'locsin_colon',
      streetName: 'Locsin Street',
      distance: 280.0,
      polyline: [
        LatLng(9.3030, 123.3068),
        LatLng(9.3053, 123.3080),
      ],
    ),
    GraphEdge(
      id: 'bacolod_araneta_highway',
      sourceId: 'b_araneta_s',
      targetId: 'b_araneta_e',
      streetName: 'Araneta National Highway',
      distance: 4500.0,
      polyline: [
        LatLng(10.65, 122.98),
        LatLng(10.66, 122.98),
        LatLng(10.67, 122.98),
        LatLng(10.68, 122.98),
        LatLng(10.69, 122.98),
      ],
    ),
    GraphEdge(
      id: 'bacolod_lacson_street',
      sourceId: 'b_lacson_s',
      targetId: 'b_lacson_e',
      streetName: 'Lacson Street',
      distance: 4500.0,
      polyline: [
        LatLng(10.67, 122.96),
        LatLng(10.67, 122.97),
        LatLng(10.67, 122.98),
        LatLng(10.67, 122.99),
        LatLng(10.67, 123.00),
      ],
    ),
    GraphEdge(
      id: 'bacolod_burgos_street',
      sourceId: 'b_burgos_s',
      targetId: 'b_burgos_e',
      streetName: 'Burgos Street',
      distance: 4500.0,
      polyline: [
        LatLng(10.66, 122.96),
        LatLng(10.67, 122.98),
        LatLng(10.68, 123.00),
      ],
    ),
    GraphEdge(
      id: 'bacolod_circumferential_road',
      sourceId: 'b_circum_s',
      targetId: 'b_circum_e',
      streetName: 'Circumferential National Highway',
      distance: 4500.0,
      polyline: [
        LatLng(10.68, 122.96),
        LatLng(10.67, 122.98),
        LatLng(10.66, 123.00),
      ],
    ),
  ];

  static RouteInfo? getOfflineRoute(LatLng start, LatLng end) {
    final routes = getOfflineRoutes(start, end);
    return routes.isNotEmpty ? routes[0] : null;
  }

  static List<RouteInfo> getOfflineRoutes(LatLng start, LatLng end) {
    // 1. Find the nearest nodes to start and end
    GraphNode? nearestStart;
    GraphNode? nearestEnd;
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

    debugPrint('OfflineRoutingData: Checking offline routes from start=$start to end=$end');
    debugPrint('OfflineRoutingData: nearestStart=${nearestStart?.name} (dist=${minStartDist.toStringAsFixed(2)} km)');
    debugPrint('OfflineRoutingData: nearestEnd=${nearestEnd?.name} (dist=${minEndDist.toStringAsFixed(2)} km)');

    // If coordinates are too far from our Dumaguete region, fall back to empty list
    if (minStartDist > 15.0 || minEndDist > 15.0 || nearestStart == null || nearestEnd == null) {
      debugPrint('OfflineRoutingData: Snapped distance is too far (> 15 km) from regional graph. Falling back.');
      return [];
    }

    final List<RouteInfo> routes = [];

    // --- Route 1: Shortest Path (Standard Dijkstra) ---
    final primaryPath = _dijkstra(nearestStart.id, nearestEnd.id, blockedEdgeIds: {});
    if (primaryPath.isNotEmpty || nearestStart.id == nearestEnd.id) {
      final primaryRoute = _buildRouteInfo(start, end, nearestStart, nearestEnd, minStartDist, primaryPath);
      if (primaryRoute != null) {
        routes.add(primaryRoute);
      }
    }

    // --- Route 2: Alternative Path (Exclude/Penalize the primary path's main edge) ---
    if (primaryPath.isNotEmpty) {
      final Set<String> primaryEdgeIds = primaryPath.map((e) => e.id).toSet();
      final alternativePath = _dijkstra(nearestStart.id, nearestEnd.id, blockedEdgeIds: primaryEdgeIds);
      if (alternativePath.isNotEmpty) {
        final alternativeRoute = _buildRouteInfo(start, end, nearestStart, nearestEnd, minStartDist, alternativePath);
        if (alternativeRoute != null && !_areRoutesIdentical(routes[0], alternativeRoute)) {
          routes.add(alternativeRoute);
        }
      } else {
        // If blocking all edges disconnected the graph, try blocking only the most significant edge
        for (final edgeToBlock in primaryPath) {
          final altPath = _dijkstra(nearestStart.id, nearestEnd.id, blockedEdgeIds: {edgeToBlock.id});
          if (altPath.isNotEmpty) {
            final altRoute = _buildRouteInfo(start, end, nearestStart, nearestEnd, minStartDist, altPath);
            if (altRoute != null && !_areRoutesIdentical(routes[0], altRoute)) {
              routes.add(altRoute);
              break; // Found one alternative
            }
          }
        }
      }
    }

    return routes;
  }

  static bool _areRoutesIdentical(RouteInfo r1, RouteInfo r2) {
    if (r1.polyline.length != r2.polyline.length) return false;
    for (int i = 0; i < r1.polyline.length; i++) {
      if (r1.polyline[i].latitude != r2.polyline[i].latitude ||
          r1.polyline[i].longitude != r2.polyline[i].longitude) {
        return false;
      }
    }
    return true;
  }

  static RouteInfo? _buildRouteInfo(
    LatLng start,
    LatLng end,
    GraphNode nearestStart,
    GraphNode nearestEnd,
    double minStartDist,
    List<GraphEdge> path,
  ) {
    final List<LatLng> fullPolyline = [];
    fullPolyline.add(start); // Start at user's actual coordinate

    final List<RouteStep> steps = [];
    double totalDistance = 0.0;
    
    // Add initial step from actual start to nearest node
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

      // Merge polyline points
      if (fullPolyline.isNotEmpty && edgePoints.isNotEmpty) {
        if (fullPolyline.last == edgePoints.first) {
          edgePoints.removeAt(0);
        }
      }
      fullPolyline.addAll(edgePoints);
      totalDistance += edge.distance;

      // Add navigation step instruction on street change
      if (edge.streetName != currentStreet) {
        currentStreet = edge.streetName;
        steps.add(
          RouteStep(
            instruction: 'Turn onto ${edge.streetName}',
            location: edgePoints.isNotEmpty ? edgePoints.first : edge.polyline.first,
            distance: edge.distance,
            duration: edge.distance / 10.0, // average 36 km/h (10m/s)
          ),
        );
      } else if (steps.isNotEmpty) {
        // Accumulate distance for same street name
        final lastIdx = steps.length - 1;
        steps[lastIdx] = RouteStep(
          instruction: steps[lastIdx].instruction,
          location: steps[lastIdx].location,
          distance: steps[lastIdx].distance + edge.distance,
          duration: steps[lastIdx].duration + (edge.distance / 10.0),
        );
      }
    }

    // Add final point to destination
    if (fullPolyline.last != end) {
      fullPolyline.add(end);
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

    // Assume average speed 36 km/h (10 m/s)
    final double totalDuration = totalDistance / 10.0;

    return RouteInfo(
      polyline: fullPolyline,
      distance: totalDistance,
      duration: totalDuration,
      steps: steps,
    );
  }

  static List<GraphEdge> _dijkstra(
    String startId,
    String endId, {
    Set<String> blockedEdgeIds = const {},
  }) {
    final Map<String, LatLng> nodePositions = {
      for (final n in nodes) n.id: n.position
    };

    double heuristic(String id) {
      final pos = nodePositions[id];
      final endPos = nodePositions[endId];
      if (pos == null || endPos == null) return 0.0;
      return DistanceService.calculateDistance(pos, endPos) * 1000.0; // meters
    }

    // gScore[node] is the cost of the cheapest path from start to node currently known.
    final Map<String, double> gScore = {
      for (final n in nodes) n.id: double.infinity
    };
    gScore[startId] = 0.0;

    // fScore[node] = gScore[node] + heuristic(node)
    final Map<String, double> fScore = {
      for (final n in nodes) n.id: double.infinity
    };
    fScore[startId] = heuristic(startId);

    // openSet contains nodes to be evaluated.
    final Set<String> openSet = {startId};

    final Map<String, GraphEdge?> previousEdges = {};

    while (openSet.isNotEmpty) {
      // Find the node in openSet having the lowest fScore value.
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

      // Find neighbors that are not blocked
      final neighbors = edges.where((e) =>
          (e.sourceId == currentId || e.targetId == currentId) &&
          !blockedEdgeIds.contains(e.id));

      for (final edge in neighbors) {
        final neighborId = edge.sourceId == currentId ? edge.targetId : edge.sourceId;
        final tentativeGScore = gScore[currentId]! + edge.distance;

        if (tentativeGScore < gScore[neighborId]!) {
          // This path to neighbor is better than any previous one. Record it!
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

    final List<GraphEdge> path = [];
    String current = endId;
    while (current != startId) {
      final edge = previousEdges[current];
      if (edge == null) break;
      path.insert(0, edge);
      current = edge.sourceId == current ? edge.targetId : edge.sourceId;
    }

    return path;
  }
}
