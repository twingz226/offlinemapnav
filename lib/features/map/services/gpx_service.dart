import 'dart:io';
import 'package:path_provider/path_provider.dart';

class GPXService {
  /// Exports a recorded track into a standard GPX file with analytics metadata embedded.
  Future<String> exportRouteWithAnalytics(
    String trackName,
    List<String> formattedPointStrings,
    double totalDistanceMeters,
    double maxSpeedMps,
    DateTime startTime,
  ) async {
    final directory = await getApplicationDocumentsDirectory();
    final tracksDir = Directory('${directory.path}/GPX_Tracks');
    
    if (!await tracksDir.exists()) {
      await tracksDir.create(recursive: true);
    }

    final sanitizedName = trackName.trim().replaceAll(RegExp(r'[^\w\s\-]'), '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${tracksDir.path}/${sanitizedName}_$timestamp.gpx');

    final endTime = DateTime.now();
    final durationSeconds = endTime.difference(startTime).inSeconds;
    final avgSpeedMps = durationSeconds > 0 ? (totalDistanceMeters / durationSeconds) : 0.0;

    // Convert speed to km/h for readability
    final double maxSpeedKmh = maxSpeedMps * 3.6;
    final double avgSpeedKmh = avgSpeedMps * 3.6;
    final double distanceKm = totalDistanceMeters / 1000.0;

    final String gpxContent = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="MapWay Offline Navigator"
  xmlns="http://www.topografix.com/GPX/1/1"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
  <metadata>
    <name>$trackName</name>
    <desc>MapWay Recorded Track Log</desc>
    <time>${startTime.toUtc().toIso8601String()}</time>
    <extensions>
      <distance_km>${distanceKm.toStringAsFixed(3)}</distance_km>
      <duration_sec>$durationSeconds</duration_sec>
      <max_speed_kmh>${maxSpeedKmh.toStringAsFixed(1)}</max_speed_kmh>
      <avg_speed_kmh>${avgSpeedKmh.toStringAsFixed(1)}</avg_speed_kmh>
    </extensions>
  </metadata>
  <trk>
    <name>$trackName</name>
    <desc>Start: ${startTime.toLocal()} | End: ${endTime.toLocal()}</desc>
    <trkseg>
${formattedPointStrings.join('')}    </trkseg>
  </trk>
</gpx>
''';

    await file.writeAsString(gpxContent);
    return file.path;
  }

  /// Lists all recorded GPX files stored on the device.
  Future<List<FileSystemEntity>> listRecordedTracks() async {
    final directory = await getApplicationDocumentsDirectory();
    final tracksDir = Directory('${directory.path}/GPX_Tracks');
    
    if (!await tracksDir.exists()) {
      return [];
    }
    
    final List<FileSystemEntity> files = await tracksDir.list().toList();
    // Sort files by last modified date (descending)
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  /// Deletes a recorded GPX file.
  Future<void> deleteTrack(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Backup compatibility for the original skeleton method.
  Future<void> exportRoute(List<String> points) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/route.gpx');
    await file.writeAsString(
      '''<gpx version="1.1">
<trk>
<trkseg>
${points.join()}
</trkseg>
</trk>
</gpx>''',
    );
  }
}
