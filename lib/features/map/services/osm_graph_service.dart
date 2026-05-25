import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'distance_service.dart';
import '../presentation/providers/download_provider.dart';

class OSMNode {
  final String id;
  final String name;
  final double latitude;
  final double longitude;

  OSMNode({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  LatLng get position => LatLng(latitude, longitude);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': latitude,
        'lng': longitude,
      };

  factory OSMNode.fromJson(Map<dynamic, dynamic> json) => OSMNode(
        id: json['id'] as String,
        name: json['name'] as String,
        latitude: json['lat'] as double,
        longitude: json['lng'] as double,
      );
}

class OSMEdge {
  final String id;
  final String sourceId;
  final String targetId;
  final double distance; // in meters
  final String streetName;
  final List<LatLng> polyline;
  final double speedLimit; // in km/h

  OSMEdge({
    required this.id,
    required this.sourceId,
    required this.targetId,
    required this.distance,
    required this.streetName,
    required this.polyline,
    required this.speedLimit,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceId': sourceId,
        'targetId': targetId,
        'distance': distance,
        'streetName': streetName,
        'polyline': polyline.map((p) => [p.latitude, p.longitude]).toList(),
        'speedLimit': speedLimit,
      };

  factory OSMEdge.fromJson(Map<dynamic, dynamic> json) => OSMEdge(
        id: json['id'] as String,
        sourceId: json['sourceId'] as String,
        targetId: json['targetId'] as String,
        distance: (json['distance'] as num).toDouble(),
        streetName: json['streetName'] as String,
        polyline: (json['polyline'] as List)
            .map((p) => LatLng((p as List)[0] as double, p[1] as double))
            .toList(),
        speedLimit: (json['speedLimit'] as num?)?.toDouble() ?? 40.0,
      );
}

class OSMGraphService {
  final _dio = Dio();

  double _parseSpeedLimit(String? maxspeed, String highway) {
    if (maxspeed == null) {
      switch (highway) {
        case 'motorway':
          return 100.0;
        case 'trunk':
          return 80.0;
        case 'primary':
          return 60.0;
        case 'secondary':
          return 50.0;
        case 'tertiary':
          return 40.0;
        case 'residential':
        case 'living_street':
          return 30.0;
        default:
          return 40.0;
      }
    }
    final digits = RegExp(r'\d+').stringMatch(maxspeed);
    if (digits != null) {
      final val = double.tryParse(digits) ?? 40.0;
      if (maxspeed.toLowerCase().contains('mph')) {
        return val * 1.60934;
      }
      return val;
    }
    return 40.0;
  }

  /// Compiles OSM data for the given bounding box and saves it to Hive.
  Future<void> compileGraphForRegion(DownloadableRegion region) async {
    final minLat = region.bounds.south;
    final minLng = region.bounds.west;
    final maxLat = region.bounds.north;
    final maxLng = region.bounds.east;

    // Overpass query for street network (highway tags)
    final query = '[out:json][timeout:60];(way["highway"]($minLat,$minLng,$maxLat,$maxLng););out body;>;out skel qt;';
    final url = 'https://overpass-api.de/api/interpreter?data=${Uri.encodeComponent(query)}';

    debugPrint('OSMGraphService: Fetching road network from Overpass: $url');
    final response = await _dio.get(url);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch OSM road network: HTTP ${response.statusCode}');
    }

    final data = response.data;
    final List elements = data['elements'] ?? [];

    final Map<String, LatLng> allNodes = {};
    final List<Map<String, dynamic>> ways = [];

    for (final element in elements) {
      final type = element['type'] as String;
      if (type == 'node') {
        final String id = element['id'].toString();
        final double lat = (element['lat'] as num).toDouble();
        final double lon = (element['lon'] as num).toDouble();
        allNodes[id] = LatLng(lat, lon);
      } else if (type == 'way') {
        final List nodeIds = element['nodes'] ?? [];
        if (nodeIds.isEmpty) continue;
        final tags = element['tags'] ?? {};

        // Filter out non-drivable paths
        final String highway = tags['highway'] ?? '';
        if (highway == 'footway' ||
            highway == 'path' ||
            highway == 'steps' ||
            highway == 'pedestrian' ||
            highway == 'cycleway') {
          continue;
        }

        ways.add({
          'id': element['id'].toString(),
          'nodes': nodeIds.map((n) => n.toString()).toList(),
          'tags': tags,
        });
      }
    }

    debugPrint('OSMGraphService: Parsed ${allNodes.length} nodes and ${ways.length} road segments.');

    // Count node frequency to identify junctions
    final Map<String, int> nodeUsage = {};
    for (final way in ways) {
      final List<String> wNodes = List<String>.from(way['nodes']);
      for (final nodeId in wNodes) {
        nodeUsage[nodeId] = (nodeUsage[nodeId] ?? 0) + 1;
      }
    }

    // Set junctions
    final Set<String> junctionIds = {};
    for (final way in ways) {
      final List<String> wNodes = List<String>.from(way['nodes']);
      if (wNodes.isNotEmpty) {
        junctionIds.add(wNodes.first);
        junctionIds.add(wNodes.last);
      }
      for (final nodeId in wNodes) {
        if ((nodeUsage[nodeId] ?? 0) > 1) {
          junctionIds.add(nodeId);
        }
      }
    }

    final List<OSMNode> graphNodes = [];
    final List<OSMEdge> graphEdges = [];
    final Set<String> addedNodeIds = {};

    for (final way in ways) {
      final String wayId = way['id'];
      final List<String> wNodes = List<String>.from(way['nodes']);
      final tags = way['tags'] as Map;
      final streetName = tags['name'] ?? tags['highway'] ?? 'Unnamed Street';
      final isOneway = tags['oneway'] == 'yes';

      if (wNodes.isEmpty) continue;

      String lastJunctionId = wNodes.first;
      List<LatLng> currentSegmentPoints = [];
      if (allNodes.containsKey(lastJunctionId)) {
        currentSegmentPoints.add(allNodes[lastJunctionId]!);
      }

      for (int i = 1; i < wNodes.length; i++) {
        final nodeId = wNodes[i];
        if (!allNodes.containsKey(nodeId)) continue;

        final pos = allNodes[nodeId]!;
        currentSegmentPoints.add(pos);

        if (junctionIds.contains(nodeId)) {
          // Calculate distance along coordinates in meters
          double distanceMeters = 0.0;
          for (int j = 0; j < currentSegmentPoints.length - 1; j++) {
            distanceMeters += DistanceService.calculateDistance(
                  currentSegmentPoints[j],
                  currentSegmentPoints[j + 1],
                ) *
                1000;
          }

          // Register node objects
          if (!addedNodeIds.contains(lastJunctionId)) {
            final startPos = allNodes[lastJunctionId]!;
            graphNodes.add(OSMNode(
              id: lastJunctionId,
              name: 'Junction $lastJunctionId',
              latitude: startPos.latitude,
              longitude: startPos.longitude,
            ));
            addedNodeIds.add(lastJunctionId);
          }
          if (!addedNodeIds.contains(nodeId)) {
            graphNodes.add(OSMNode(
              id: nodeId,
              name: 'Junction $nodeId',
              latitude: pos.latitude,
              longitude: pos.longitude,
            ));
            addedNodeIds.add(nodeId);
          }

          // Register edge object
          final double limit = _parseSpeedLimit(tags['maxspeed']?.toString(), tags['highway']?.toString() ?? '');
          final edgeId = '${wayId}_${lastJunctionId}_$nodeId';
          graphEdges.add(OSMEdge(
            id: edgeId,
            sourceId: lastJunctionId,
            targetId: nodeId,
            distance: distanceMeters,
            streetName: streetName,
            polyline: List<LatLng>.from(currentSegmentPoints),
            speedLimit: limit,
          ));

          if (!isOneway) {
            final reverseEdgeId = '${wayId}_${nodeId}_$lastJunctionId';
            graphEdges.add(OSMEdge(
              id: reverseEdgeId,
              sourceId: nodeId,
              targetId: lastJunctionId,
              distance: distanceMeters,
              streetName: streetName,
              polyline: List<LatLng>.from(currentSegmentPoints.reversed),
              speedLimit: limit,
            ));
          }

          lastJunctionId = nodeId;
          currentSegmentPoints = [pos];
        }
      }
    }

    debugPrint('OSMGraphService: Compiled ${graphNodes.length} nodes and ${graphEdges.length} edges.');

    // Write compiled graph to Hive box
    final box = await Hive.openBox('osm_graphs');
    await box.put('${region.id}_nodes', graphNodes.map((n) => n.toJson()).toList());
    await box.put('${region.id}_edges', graphEdges.map((e) => e.toJson()).toList());
    
    debugPrint('OSMGraphService: Compiled graph saved under key prefix: ${region.id}');
  }

  /// Checks if a region has a compiled offline graph available.
  Future<bool> hasGraphForRegion(String regionId) async {
    final box = await Hive.openBox('osm_graphs');
    return box.containsKey('${regionId}_nodes');
  }

  /// Deletes a compiled offline graph from cache.
  Future<void> deleteGraphForRegion(String regionId) async {
    final box = await Hive.openBox('osm_graphs');
    await box.delete('${regionId}_nodes');
    await box.delete('${regionId}_edges');
  }
}

final osmGraphServiceProvider = Provider<OSMGraphService>((ref) {
  return OSMGraphService();
});
