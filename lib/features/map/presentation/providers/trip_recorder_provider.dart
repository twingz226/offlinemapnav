import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/gpx_service.dart';
import 'location_provider.dart';

class TripPoint {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double speed;
  final double elevation;

  TripPoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.speed = 0.0,
    this.elevation = 0.0,
  });
}

class TripRecorderState {
  final bool isRecording;
  final List<TripPoint> points;
  final double totalDistance; // in meters
  final double maxSpeed; // in m/s
  final DateTime? startTime;

  TripRecorderState({
    required this.isRecording,
    required this.points,
    required this.totalDistance,
    required this.maxSpeed,
    this.startTime,
  });

  TripRecorderState copyWith({
    bool? isRecording,
    List<TripPoint>? points,
    double? totalDistance,
    double? maxSpeed,
    DateTime? startTime,
  }) {
    return TripRecorderState(
      isRecording: isRecording ?? this.isRecording,
      points: points ?? this.points,
      totalDistance: totalDistance ?? this.totalDistance,
      maxSpeed: maxSpeed ?? this.maxSpeed,
      startTime: startTime ?? this.startTime,
    );
  }
}

class TripRecorderNotifier extends StateNotifier<TripRecorderState> {
  final GPXService _gpxService = GPXService();
  ProviderSubscription<AsyncValue<Position?>>? _locationSubscription;
  final Ref _ref;

  TripRecorderNotifier(this._ref)
      : super(TripRecorderState(
          isRecording: false,
          points: [],
          totalDistance: 0.0,
          maxSpeed: 0.0,
        ));

  void startRecording() {
    state = TripRecorderState(
      isRecording: true,
      points: [],
      totalDistance: 0.0,
      maxSpeed: 0.0,
      startTime: DateTime.now(),
    );

    _locationSubscription?.close();
    
    // Listen to location updates while recording is active
    _locationSubscription = _ref.listen<AsyncValue<Position?>>(
      locationProvider,
      (previous, next) {
        final position = next.value;
        if (position != null && state.isRecording) {
          _addPosition(position);
        }
      },
    );
  }

  void _addPosition(Position pos) {
    final newPoint = TripPoint(
      latitude: pos.latitude,
      longitude: pos.longitude,
      timestamp: pos.timestamp,
      speed: pos.speed,
      elevation: pos.altitude,
    );

    double addedDistance = 0.0;
    if (state.points.isNotEmpty) {
      final lastPoint = state.points.last;
      addedDistance = Geolocator.distanceBetween(
        lastPoint.latitude,
        lastPoint.longitude,
        newPoint.latitude,
        newPoint.longitude,
      );
    }

    final double newMaxSpeed = pos.speed > state.maxSpeed ? pos.speed : state.maxSpeed;
    final double newTotalDistance = state.totalDistance + addedDistance;

    state = state.copyWith(
      points: [...state.points, newPoint],
      totalDistance: newTotalDistance,
      maxSpeed: newMaxSpeed,
    );
  }

  void pauseRecording() {
    state = state.copyWith(isRecording: false);
    _locationSubscription?.close();
  }

  void resumeRecording() {
    state = state.copyWith(isRecording: true);
    _locationSubscription?.close();
    _locationSubscription = _ref.listen<AsyncValue<Position?>>(
      locationProvider,
      (previous, next) {
        final position = next.value;
        if (position != null && state.isRecording) {
          _addPosition(position);
        }
      },
    );
  }

  void stopRecording() {
    _locationSubscription?.close();
    state = state.copyWith(isRecording: false);
  }

  Future<String?> saveCurrentTrip(String name) async {
    if (state.points.isEmpty) {
      state = TripRecorderState(
        isRecording: false,
        points: [],
        totalDistance: 0.0,
        maxSpeed: 0.0,
      );
      return null;
    }

    final formattedPoints = state.points.map((p) {
      return '      <trkpt lat="${p.latitude}" lon="${p.longitude}">\n'
             '        <ele>${p.elevation}</ele>\n'
             '        <time>${p.timestamp.toUtc().toIso8601String()}</time>\n'
             '        <extensions>\n'
             '          <speed>${p.speed}</speed>\n'
             '        </extensions>\n'
             '      </trkpt>\n';
    }).toList();

    try {
      final filePath = await _gpxService.exportRouteWithAnalytics(
        name,
        formattedPoints,
        state.totalDistance,
        state.maxSpeed,
        state.startTime ?? DateTime.now(),
      );
      
      state = TripRecorderState(
        isRecording: false,
        points: [],
        totalDistance: 0.0,
        maxSpeed: 0.0,
      );
      
      return filePath;
    } catch (e) {
      return null;
    }
  }

  void discardRecording() {
    _locationSubscription?.close();
    state = TripRecorderState(
      isRecording: false,
      points: [],
      totalDistance: 0.0,
      maxSpeed: 0.0,
    );
  }

  @override
  void dispose() {
    _locationSubscription?.close();
    super.dispose();
  }
}


final tripRecorderProvider =
    StateNotifierProvider<TripRecorderNotifier, TripRecorderState>((ref) {
  return TripRecorderNotifier(ref);
});
