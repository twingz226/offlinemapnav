import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/route_history_service.dart';

final routeHistoryProvider = StateNotifierProvider<RouteHistoryNotifier, List<RouteHistoryItem>>((ref) {
  return RouteHistoryNotifier();
});

class RouteHistoryNotifier extends StateNotifier<List<RouteHistoryItem>> {
  RouteHistoryNotifier() : super([]) {
    loadHistory();
  }

  final _service = RouteHistoryService();

  void loadHistory() {
    state = _service.getHistory();
  }

  Future<void> addRouteHistory({
    required String startName,
    required String endName,
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
    required double distance,
    required double duration,
    List<String> viaStreets = const [],
  }) async {
    // Check for duplicates in the last 2 minutes
    final now = DateTime.now();
    final duplicates = state.where((item) {
      final timeDiff = now.difference(item.createdAt).inMinutes.abs();
      final isSameStart = (item.startLat - startLat).abs() < 0.0001 && (item.startLng - startLng).abs() < 0.0001;
      final isSameEnd = (item.endLat - endLat).abs() < 0.0001 && (item.endLng - endLng).abs() < 0.0001;
      return timeDiff < 2 && isSameStart && isSameEnd;
    });

    if (duplicates.isNotEmpty) {
      return; // Skip duplicating route calculation entries
    }

    await _service.saveRoute(
      startName: startName,
      endName: endName,
      startLat: startLat,
      startLng: startLng,
      endLat: endLat,
      endLng: endLng,
      distance: distance,
      duration: duration,
      viaStreets: viaStreets,
    );
    loadHistory();
  }

  Future<void> deleteItem(String id) async {
    await _service.deleteItem(id);
    loadHistory();
  }

  Future<void> clearHistory() async {
    await _service.clearHistory();
    loadHistory();
  }
}
