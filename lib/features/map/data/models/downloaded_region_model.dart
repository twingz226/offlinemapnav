class DownloadedRegionModel {
  final String id;
  final String name;
  final double north;
  final double south;
  final double east;
  final double west;
  final int minZoom;
  final int maxZoom;
  final double sizeMB;

  DownloadedRegionModel({
    required this.id,
    required this.name,
    required this.north,
    required this.south,
    required this.east,
    required this.west,
    required this.minZoom,
    required this.maxZoom,
    required this.sizeMB,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'north': north,
      'south': south,
      'east': east,
      'west': west,
      'minZoom': minZoom,
      'maxZoom': maxZoom,
      'sizeMB': sizeMB,
    };
  }

  factory DownloadedRegionModel.fromJson(Map json) {
    return DownloadedRegionModel(
      id: json['id'],
      name: json['name'],
      north: json['north'],
      south: json['south'],
      east: json['east'],
      west: json['west'],
      minZoom: json['minZoom'],
      maxZoom: json['maxZoom'],
      sizeMB: (json['sizeMB'] as num).toDouble(),
    );
  }
}
