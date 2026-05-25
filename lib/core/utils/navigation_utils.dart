import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import '../../features/map/services/distance_service.dart';

class KalmanFilter2D {
  final double q; // Process noise covariance
  final double r; // Measurement noise covariance
  
  double? _lat;   // Estimated latitude
  double? _lng;   // Estimated longitude
  double _p = 10.0; // Estimation error covariance

  KalmanFilter2D({this.q = 0.0001, this.r = 0.001});

  LatLng filter(LatLng point) {
    if (_lat == null || _lng == null) {
      _lat = point.latitude;
      _lng = point.longitude;
      return point;
    }
    
    // Prediction update
    _p = _p + q;
    
    // Measurement update (Kalman Gain)
    final double k = _p / (_p + r);
    _lat = _lat! + k * (point.latitude - _lat!);
    _lng = _lng! + k * (point.longitude - _lng!);
    _p = (1 - k) * _p;
    
    return LatLng(_lat!, _lng!);
  }

  void reset() {
    _lat = null;
    _lng = null;
    _p = 10.0;
  }
}

class NavigationUtils {
  /// Snaps a GPS coordinate [point] to the closest point along the route [polyline].
  /// If the closest segment is within [maxSnapDistanceMeters], returns the snapped position
  /// and the index of the segment. Otherwise, returns the original point and -1.
  static (LatLng snappedPoint, int segmentIndex) snapToRoute({
    required LatLng point,
    required List<LatLng> polyline,
    required double maxSnapDistanceMeters,
  }) {
    if (polyline.isEmpty) return (point, -1);
    if (polyline.length == 1) return (polyline.first, 0);

    LatLng bestSnapped = point;
    double minDistance = double.infinity;
    int bestSegmentIndex = -1;

    for (int i = 0; i < polyline.length - 1; i++) {
      final a = polyline[i];
      final b = polyline[i + 1];

      final snapped = _projectPointOnSegment(point, a, b);
      final dist = DistanceService.calculateDistance(point, snapped) * 1000.0; // in meters

      if (dist < minDistance) {
        minDistance = dist;
        bestSnapped = snapped;
        bestSegmentIndex = i;
      }
    }

    if (minDistance <= maxSnapDistanceMeters) {
      return (bestSnapped, bestSegmentIndex);
    }

    return (point, -1);
  }

  /// Calculates the bearing in degrees between two LatLng coordinates (from 0 to 360).
  static double calculateBearing(LatLng start, LatLng end) {
    final double lat1 = start.latitude * math.pi / 180.0;
    final double lon1 = start.longitude * math.pi / 180.0;
    final double lat2 = end.latitude * math.pi / 180.0;
    final double lon2 = end.longitude * math.pi / 180.0;

    final double dLon = lon2 - lon1;

    final double y = math.sin(dLon) * math.cos(lat2);
    final double x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    double bearing = math.atan2(y, x) * 180.0 / math.pi;
    bearing = (bearing + 360.0) % 360.0;
    return bearing;
  }

  /// Projects point [p] onto segment [a] -> [b].
  static LatLng _projectPointOnSegment(LatLng p, LatLng a, LatLng b) {
    final double x = p.longitude;
    final double y = p.latitude;
    final double x1 = a.longitude;
    final double y1 = a.latitude;
    final double x2 = b.longitude;
    final double y2 = b.latitude;

    final double dx = x2 - x1;
    final double dy = y2 - y1;

    if (dx == 0 && dy == 0) {
      return a;
    }

    final double t = ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy);

    if (t < 0) {
      return a;
    } else if (t > 1) {
      return b;
    }

    return LatLng(
      y1 + t * dy,
      x1 + t * dx,
    );
  }
}
