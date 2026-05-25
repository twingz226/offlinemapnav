import 'dart:io';

class GPXService {

  Future<void> exportRoute(
    List<String> points,
  ) async {

    final file = File(
      '/storage/emulated/0/Download/route.gpx',
    );

    await file.writeAsString(
      '''
<gpx version="1.1">
<trk>
<trkseg>

${points.join()}

</trkseg>
</trk>
</gpx>
''',
    );
  }
}
