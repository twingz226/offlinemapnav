class RouteHistoryModel {

  final String startName;
  final String endName;

  final double startLat;
  final double startLng;

  final double endLat;
  final double endLng;

  final DateTime createdAt;

  RouteHistoryModel({
    required this.startName,
    required this.endName,
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
    required this.createdAt,
  });
}
