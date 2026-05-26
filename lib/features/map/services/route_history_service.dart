import 'package:hive/hive.dart';

class RouteHistoryItem {
  final String id;
  final String startName;
  final String endName;
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;
  final double distance; // in meters
  final double duration; // in seconds
  final double averageSpeedKmh; // in km/h
  final DateTime createdAt;

  RouteHistoryItem({
    required this.id,
    required this.startName,
    required this.endName,
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
    required this.distance,
    required this.duration,
    required this.averageSpeedKmh,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'startName': startName,
        'endName': endName,
        'startLat': startLat,
        'startLng': startLng,
        'endLat': endLat,
        'endLng': endLng,
        'distance': distance,
        'duration': duration,
        'averageSpeedKmh': averageSpeedKmh,
        'createdAt': createdAt.toIso8601String(),
      };

  factory RouteHistoryItem.fromJson(Map<dynamic, dynamic> json) {
    final double dist = (json['distance'] as num).toDouble();
    final double dur = (json['duration'] as num).toDouble();
    final double avgSpeed = (json['averageSpeedKmh'] as num?)?.toDouble() ?? 
                            (dur > 0 ? (dist / dur) * 3.6 : 0.0);
    return RouteHistoryItem(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      startName: json['startName'] as String? ?? 'Unknown Start',
      endName: json['endName'] as String? ?? 'Unknown Destination',
      startLat: (json['startLat'] as num).toDouble(),
      startLng: (json['startLng'] as num).toDouble(),
      endLat: (json['endLat'] as num).toDouble(),
      endLng: (json['endLng'] as num).toDouble(),
      distance: dist,
      duration: dur,
      averageSpeedKmh: avgSpeed,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class RouteHistoryService {
  static const String _boxName = 'routesHistory';

  Future<void> saveRoute({
    required String startName,
    required String endName,
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
    required double distance,
    required double duration,
  }) async {
    try {
      final box = Hive.box(_boxName);
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final double averageSpeedKmh = duration > 0 ? (distance / duration) * 3.6 : 0.0;
      
      final item = RouteHistoryItem(
        id: id,
        startName: startName,
        endName: endName,
        startLat: startLat,
        startLng: startLng,
        endLat: endLat,
        endLng: endLng,
        distance: distance,
        duration: duration,
        averageSpeedKmh: averageSpeedKmh,
        createdAt: DateTime.now(),
      );

      await box.put(id, item.toJson());
    } catch (_) {
      // Ignore
    }
  }

  List<RouteHistoryItem> getHistory() {
    try {
      final box = Hive.box(_boxName);
      final list = box.values.map((v) => RouteHistoryItem.fromJson(v as Map)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteItem(String id) async {
    try {
      final box = Hive.box(_boxName);
      await box.delete(id);
    } catch (_) {}
  }

  Future<void> clearHistory() async {
    try {
      final box = Hive.box(_boxName);
      await box.clear();
    } catch (_) {}
  }
}
