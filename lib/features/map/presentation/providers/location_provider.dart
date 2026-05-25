import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/location_service.dart';

final locationProvider =
    StateNotifierProvider<LocationNotifier, AsyncValue<Position?>>(
  (ref) => LocationNotifier(LocationService()),
);

class LocationNotifier extends StateNotifier<AsyncValue<Position?>> {
  final LocationService _service;
  StreamSubscription<Position>? _subscription;

  LocationNotifier(this._service) : super(const AsyncValue.loading()) {
    getCurrentLocation();
    _startLocationUpdates();
  }

  void _startLocationUpdates() {
    _subscription?.cancel();
    _subscription = _service.getStream(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2, // 2 meters threshold for high responsiveness in navigation
    ).listen((position) {
      state = AsyncValue.data(position);
    }, onError: (e) {
      state = AsyncValue.error(e, StackTrace.current);
    });
  }

  Future<Position?> getCurrentLocation() async {
    try {
      final pos = await _service.getCurrentPosition();
      state = AsyncValue.data(pos);
      return pos;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return null;
    }
  }

  Future<Position?> getLastKnownLocation() async {
    try {
      final pos = await _service.getLastKnownPosition();
      if (pos != null) {
        state = AsyncValue.data(pos);
      }
      return pos;
    } catch (_) {
      return null;
    }
  }

  void centerOnUser() {
    getCurrentLocation();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
