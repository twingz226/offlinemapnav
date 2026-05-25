import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:offline_map/core/utils/navigation_utils.dart';
import '../../services/routing_service.dart';
import '../../services/voice_navigation_service.dart';
import '../../services/distance_service.dart';
import 'location_provider.dart';

class NavigationState {
  final RouteInfo? activeRoute;
  final List<RouteInfo> alternativeRoutes;
  final bool isNavigating;
  final LatLng? destination;
  final String? destinationName;
  final int currentStepIndex;
  final double remainingDistance; // in meters
  final double remainingDuration; // in seconds
  final bool isRerouting;
  final Position? snappedPosition;

  NavigationState({
    this.activeRoute,
    this.alternativeRoutes = const [],
    this.isNavigating = false,
    this.destination,
    this.destinationName,
    this.currentStepIndex = 0,
    this.remainingDistance = 0,
    this.remainingDuration = 0,
    this.isRerouting = false,
    this.snappedPosition,
  });

  NavigationState copyWith({
    RouteInfo? Function()? activeRoute,
    List<RouteInfo>? alternativeRoutes,
    bool? isNavigating,
    LatLng? Function()? destination,
    String? Function()? destinationName,
    int? currentStepIndex,
    double? remainingDistance,
    double? remainingDuration,
    bool? isRerouting,
    Position? Function()? snappedPosition,
  }) {
    return NavigationState(
      activeRoute: activeRoute != null ? activeRoute() : this.activeRoute,
      alternativeRoutes: alternativeRoutes ?? this.alternativeRoutes,
      isNavigating: isNavigating ?? this.isNavigating,
      destination: destination != null ? destination() : this.destination,
      destinationName: destinationName != null ? destinationName() : this.destinationName,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      remainingDistance: remainingDistance ?? this.remainingDistance,
      remainingDuration: remainingDuration ?? this.remainingDuration,
      isRerouting: isRerouting ?? this.isRerouting,
      snappedPosition: snappedPosition != null ? snappedPosition() : this.snappedPosition,
    );
  }

  String get formattedRemainingDistance {
    if (remainingDistance < 1000) {
      return '${remainingDistance.toStringAsFixed(0)} m';
    }
    final double distInKm = remainingDistance / 1000;
    return '${distInKm.toStringAsFixed(1)} km';
  }

  String get formattedETA {
    final int totalMinutes = (remainingDuration / 60).round();
    if (totalMinutes < 60) {
      return '$totalMinutes min';
    }
    final int hours = totalMinutes ~/ 60;
    final int minutes = totalMinutes % 60;
    return '${hours}h ${minutes}m';
  }
}

class NavigationNotifier extends StateNotifier<NavigationState> {
  NavigationNotifier(this.ref) : super(NavigationState()) {
    // Listen to user location updates to update progress or reroute
    ref.listen(locationProvider, (previous, next) {
      next.whenData((position) {
        if (position != null && state.isNavigating) {
          _onLocationUpdated(position);
        }
      });
    });
  }

  final _kalmanFilter = KalmanFilter2D();

  final Ref ref;
  final _routingService = RoutingService();
  final _voiceService = VoiceNavigationService();
  
  int _lastSpokenStepIndex = -1;
  double _lastSpokenDistance = double.infinity;

  Future<void> startNavigation({
    required LatLng start,
    required LatLng end,
    required String destinationName,
  }) async {
    _kalmanFilter.reset();
    state = state.copyWith(
      isNavigating: true,
      destination: () => end,
      destinationName: () => destinationName,
      isRerouting: true,
      snappedPosition: () => null,
    );

    // Direct check to avoid Riverpod StreamProvider initial loading lag
    bool isOnline = false;
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      isOnline = !connectivityResult.contains(ConnectivityResult.none);
    } catch (_) {}

    try {
      final routes = await _routingService.getRoutes(
        start: start,
        end: end,
        isOnline: isOnline,
      );

      if (routes.isNotEmpty) {
        final primaryRoute = routes[0];
        final alts = routes.sublist(1);

        state = state.copyWith(
          activeRoute: () => primaryRoute,
          alternativeRoutes: alts,
          currentStepIndex: 0,
          remainingDistance: primaryRoute.distance,
          remainingDuration: primaryRoute.duration,
          isRerouting: false,
        );

        _lastSpokenStepIndex = -1;
        _lastSpokenDistance = double.infinity;
        
        if (primaryRoute.steps.isNotEmpty) {
          _speakStep(0, primaryRoute.steps[0].instruction);
        }
      } else {
        state = state.copyWith(isNavigating: false, isRerouting: false);
      }
    } catch (_) {
      state = state.copyWith(isNavigating: false, isRerouting: false);
    }
  }

  Future<void> calculateRoutes({
    required LatLng start,
    required LatLng end,
    required String destinationName,
  }) async {
    state = state.copyWith(
      isNavigating: false,
      destination: () => end,
      destinationName: () => destinationName,
      isRerouting: true,
      activeRoute: () => null,
      alternativeRoutes: [],
    );

    bool isOnline = false;
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      isOnline = !connectivityResult.contains(ConnectivityResult.none);
    } catch (_) {}

    try {
      final routes = await _routingService.getRoutes(
        start: start,
        end: end,
        isOnline: isOnline,
      );

      if (routes.isNotEmpty) {
        final primaryRoute = routes[0];
        final alts = routes.sublist(1);

        state = state.copyWith(
          activeRoute: () => primaryRoute,
          alternativeRoutes: alts,
          currentStepIndex: 0,
          remainingDistance: primaryRoute.distance,
          remainingDuration: primaryRoute.duration,
          isRerouting: false,
        );
      } else {
        state = state.copyWith(isRerouting: false);
      }
    } catch (_) {
      state = state.copyWith(isRerouting: false);
    }
  }

  void selectAlternativeRoute(RouteInfo route) {
    if (state.activeRoute == null) return;
    
    final List<RouteInfo> newAlts = List.from(state.alternativeRoutes);
    final prevActive = state.activeRoute!;
    
    // Remove the chosen alternative and add the previous active route to the alternatives list
    newAlts.removeWhere((r) => r.polyline == route.polyline);
    newAlts.add(prevActive);
    
    state = state.copyWith(
      activeRoute: () => route,
      alternativeRoutes: newAlts,
      currentStepIndex: 0,
      remainingDistance: route.distance,
      remainingDuration: route.duration,
    );
  }

  void startGuidance() {
    if (state.activeRoute == null) return;
    
    state = state.copyWith(
      isNavigating: true,
    );
    
    _lastSpokenStepIndex = -1;
    _lastSpokenDistance = double.infinity;
    
    if (state.activeRoute!.steps.isNotEmpty) {
      _speakStep(0, state.activeRoute!.steps[0].instruction);
    }
  }

  void stopNavigation() {
    state = NavigationState();
    _lastSpokenStepIndex = -1;
    _lastSpokenDistance = double.infinity;
    _kalmanFilter.reset();
    _voiceService.speak("Navigation stopped");
  }

  Future<void> _onLocationUpdated(Position rawPosition) async {
    final route = state.activeRoute;
    if (route == null || state.isRerouting) return;

    final rawLatLng = LatLng(rawPosition.latitude, rawPosition.longitude);
    final filteredLatLng = _kalmanFilter.filter(rawLatLng);

    // 1. Reroute Detection (User moves > 65 meters away from closest point on route)
    final distToRoute = _distanceToPolyline(filteredLatLng, route.polyline);
    if (distToRoute > 65.0) {
      _triggerReroute(rawLatLng);
      return;
    }

    // 2. Snap to Route
    final (snappedLatLng, segmentIndex) = NavigationUtils.snapToRoute(
      point: filteredLatLng,
      polyline: route.polyline,
      maxSnapDistanceMeters: 30.0,
    );

    // Calculate heading from snapped segment bearing if available
    double heading = rawPosition.heading;
    if (segmentIndex != -1 && segmentIndex < route.polyline.length - 1) {
      heading = NavigationUtils.calculateBearing(
        route.polyline[segmentIndex],
        route.polyline[segmentIndex + 1],
      );
    }

    // Construct snapped position object
    final snappedPos = Position(
      latitude: snappedLatLng.latitude,
      longitude: snappedLatLng.longitude,
      timestamp: rawPosition.timestamp,
      accuracy: rawPosition.accuracy,
      altitude: rawPosition.altitude,
      altitudeAccuracy: rawPosition.altitudeAccuracy,
      heading: heading,
      headingAccuracy: rawPosition.headingAccuracy,
      speed: rawPosition.speed,
      speedAccuracy: rawPosition.speedAccuracy,
      isMocked: rawPosition.isMocked,
    );

    state = state.copyWith(snappedPosition: () => snappedPos);

    // 3. Advance Steps Check
    final steps = route.steps;
    int currentIndex = state.currentStepIndex;
    
    if (currentIndex < steps.length) {
      final nextStepLoc = steps[currentIndex].location;
      final distToNextTurn = DistanceService.calculateDistance(snappedLatLng, nextStepLoc) * 1000;

      if (distToNextTurn < 25.0 && currentIndex + 1 < steps.length) {
        currentIndex++;
        state = state.copyWith(currentStepIndex: currentIndex);
        _speakStep(currentIndex, steps[currentIndex].instruction);
      } else {
        // Turn announcements
        if (distToNextTurn < 100.0 && distToNextTurn > 75.0 && _lastSpokenDistance > 100.0) {
          _lastSpokenDistance = 100.0;
          _voiceService.speak("In 100 meters, ${steps[currentIndex].instruction}");
        } else if (distToNextTurn < 40.0 && distToNextTurn > 25.0 && _lastSpokenDistance > 40.0) {
          _lastSpokenDistance = 40.0;
          _voiceService.speak("In 40 meters, ${steps[currentIndex].instruction}");
        }
      }
    }

    // 4. Estimate Remaining Distance & Duration along remaining route polyline
    double remainingDist = 0.0;
    int closestNodeIndex = 0;
    double minNodeDist = double.infinity;

    for (int i = 0; i < route.polyline.length; i++) {
      final d = DistanceService.calculateDistance(snappedLatLng, route.polyline[i]) * 1000;
      if (d < minNodeDist) {
        minNodeDist = d;
        closestNodeIndex = i;
      }
    }

    remainingDist += minNodeDist;
    for (int i = closestNodeIndex; i < route.polyline.length - 1; i++) {
      remainingDist += DistanceService.calculateDistance(route.polyline[i], route.polyline[i + 1]) * 1000;
    }

    // Average driving speed fallback 36 km/h (10 m/s)
    final double remainingDur = remainingDist / 10.0;

    state = state.copyWith(
      remainingDistance: remainingDist,
      remainingDuration: remainingDur,
    );

    // 5. Arrived Destination Check
    if (state.destination != null) {
      final distToDest = DistanceService.calculateDistance(snappedLatLng, state.destination!) * 1000;
      if (distToDest < 20.0) {
        _voiceService.speak("You have arrived at your destination");
        stopNavigation();
      }
    }
  }

  Future<void> _triggerReroute(LatLng userPos) async {
    if (state.destination == null || state.isRerouting) return;
    
    state = state.copyWith(isRerouting: true);
    _voiceService.speak("Recalculating route");

    // Direct check to avoid Riverpod StreamProvider initial loading lag
    bool isOnline = false;
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      isOnline = !connectivityResult.contains(ConnectivityResult.none);
    } catch (_) {}

    try {
      final routes = await _routingService.getRoutes(
        start: userPos,
        end: state.destination!,
        isOnline: isOnline,
      );

      if (routes.isNotEmpty) {
        final primaryRoute = routes[0];
        final alts = routes.sublist(1);

        state = state.copyWith(
          activeRoute: () => primaryRoute,
          alternativeRoutes: alts,
          currentStepIndex: 0,
          remainingDistance: primaryRoute.distance,
          remainingDuration: primaryRoute.duration,
          isRerouting: false,
        );

        _lastSpokenStepIndex = -1;
        _lastSpokenDistance = double.infinity;

        if (primaryRoute.steps.isNotEmpty) {
          _speakStep(0, primaryRoute.steps[0].instruction);
        }
      } else {
        state = state.copyWith(isRerouting: false);
      }
    } catch (_) {
      state = state.copyWith(isRerouting: false);
    }
  }

  void _speakStep(int stepIndex, String instruction) {
    if (stepIndex != _lastSpokenStepIndex) {
      _lastSpokenStepIndex = stepIndex;
      _lastSpokenDistance = double.infinity;
      _voiceService.speak(instruction);
    }
  }

  double _distanceToPolyline(LatLng point, List<LatLng> polyline) {
    if (polyline.isEmpty) return double.infinity;
    double minDistance = double.infinity;
    for (final node in polyline) {
      final d = DistanceService.calculateDistance(point, node) * 1000;
      if (d < minDistance) {
        minDistance = d;
      }
    }
    return minDistance;
  }
}

final navigationProvider = StateNotifierProvider<NavigationNotifier, NavigationState>((ref) {
  return NavigationNotifier(ref);
});
