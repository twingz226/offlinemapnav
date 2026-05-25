import 'package:latlong2/latlong.dart';

class DistanceService {

  static double calculateDistance(
    LatLng start,
    LatLng end,
  ) {

    const Distance distance = Distance();

    return distance.as(
      LengthUnit.Kilometer,
      start,
      end,
    );
  }
}
