import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:offline_map/core/utils/navigation_utils.dart';
import 'package:hive/hive.dart';
import '../../services/routing_service.dart';
import '../../services/voice_navigation_service.dart';
import '../../services/distance_service.dart';
import '../../services/administrative_boundary_service.dart';
import 'location_provider.dart';
import 'route_history_provider.dart';

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
  final double currentSpeedLimit; // in km/h

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
    this.currentSpeedLimit = 40.0,
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
    double? currentSpeedLimit,
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
      currentSpeedLimit: currentSpeedLimit ?? this.currentSpeedLimit,
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
  final _boundaryService = AdministrativeBoundaryService();
  
  int _lastSpokenStepIndex = -1;
  double _lastSpokenDistance = double.infinity;
  DateTime? _lastSpeedWarningTime;


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

        final resolvedStartName = await _resolvePlaceName(start, 'Current Location', isOnline);
        final resolvedEndName = await _resolvePlaceName(end, destinationName, isOnline);

        ref.read(routeHistoryProvider.notifier).addRouteHistory(
          startName: resolvedStartName,
          endName: resolvedEndName,
          startLat: start.latitude,
          startLng: start.longitude,
          endLat: end.latitude,
          endLng: end.longitude,
          distance: primaryRoute.distance,
          duration: primaryRoute.duration,
          viaStreets: _extractViaStreets(primaryRoute),
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

        final resolvedStartName = await _resolvePlaceName(start, 'Current Location', isOnline);
        final resolvedEndName = await _resolvePlaceName(end, destinationName, isOnline);

        ref.read(routeHistoryProvider.notifier).addRouteHistory(
          startName: resolvedStartName,
          endName: resolvedEndName,
          startLat: start.latitude,
          startLng: start.longitude,
          endLat: end.latitude,
          endLng: end.longitude,
          distance: primaryRoute.distance,
          duration: primaryRoute.duration,
          viaStreets: _extractViaStreets(primaryRoute),
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

    // Get speed limit for current segment
    double currentLimit = 40.0;
    if (route.speedLimits != null &&
        segmentIndex >= 0 &&
        segmentIndex < route.speedLimits!.length) {
      currentLimit = route.speedLimits![segmentIndex];
    }

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

    // Speed Warning Check (warn user via TTS once every 30s)
    final currentSpeedKmh = rawPosition.speed * 3.6;
    if (currentSpeedKmh > currentLimit * 1.1) {
      final now = DateTime.now();
      if (_lastSpeedWarningTime == null ||
          now.difference(_lastSpeedWarningTime!).inSeconds > 30) {
        _lastSpeedWarningTime = now;
        _voiceService.speak("Warning, you are exceeding the speed limit!");
      }
    }

    state = state.copyWith(
      snappedPosition: () => snappedPos,
      currentSpeedLimit: currentLimit,
    );


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

  String _getOfflinePlaceName(LatLng point) {
    try {
      final box = Hive.box('downloaded_places');
      String? bestName;
      double minDistance = double.infinity;

      for (final key in box.keys) {
        final val = box.get(key);
        if (val is Map) {
          final name = val['name'] as String?;
          final south = val['south'] as double?;
          final west = val['west'] as double?;
          final north = val['north'] as double?;
          final east = val['east'] as double?;
          if (name != null && south != null && west != null && north != null && east != null) {
            if (point.latitude >= south &&
                point.latitude <= north &&
                point.longitude >= west &&
                point.longitude <= east) {
              final centerLat = (south + north) / 2;
              final centerLng = (west + east) / 2;
              final dist = DistanceService.calculateDistance(
                point,
                LatLng(centerLat, centerLng),
              );
              if (dist < minDistance) {
                minDistance = dist;
                bestName = name;
              }
            }
          }
        }
      }
      if (bestName != null) {
        return bestName;
      }
    } catch (_) {}
    return 'Current Location';
  }

  Future<String> _resolvePlaceName(LatLng point, String fallback, bool isOnline) async {
    // If the fallback is already a valid specific place name, use it directly!
    if (fallback.isNotEmpty && 
        fallback != 'Current Location' && 
        fallback != 'Pinned Location' && 
        fallback != 'Destination') {
      return fallback;
    }

    // 1. Try to resolve using offline downloaded places bounds
    String offlineName = _getOfflinePlaceName(point);
    if (offlineName != 'Current Location') {
      return offlineName;
    }

    // 2. If online and not found offline, try reverse-geocoding
    if (isOnline) {
      try {
        final place = await _boundaryService.getPlaceForLocation(point.latitude, point.longitude);
        if (place != null && place.name.isNotEmpty) {
          return place.name;
        }
      } catch (_) {}
    }

    // 3. Clean up generic fallbacks or return fallback
    if (fallback == 'Current Location' || fallback == 'Pinned Location' || fallback.isEmpty) {
      return 'Location (${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)})';
    }
    return fallback;
  }

  List<String> _extractViaStreets(RouteInfo route) {
    final Set<String> streets = {};
    final patterns = [
      RegExp(r'on\s+(.+)$', caseSensitive: false),
      RegExp(r'onto\s+(.+)$', caseSensitive: false),
      RegExp(r'toward\s+(.+)$', caseSensitive: false),
    ];

    for (final step in route.steps) {
      final instruction = step.instruction;
      for (final pattern in patterns) {
        final match = pattern.firstMatch(instruction);
        if (match != null) {
          final street = match.group(1)!.trim();
          if (street.isNotEmpty &&
              street.toLowerCase() != 'starting point' &&
              street.toLowerCase() != 'destination' &&
              street.toLowerCase() != 'unnamed road') {
            final cleaned = street.replaceAll(RegExp(r'[.,]$'), '');
            streets.add(cleaned);
          }
        }
      }
    }
    return streets.toList();
  }
}

final navigationProvider = StateNotifierProvider<NavigationNotifier, NavigationState>((ref) {
  return NavigationNotifier(ref);
});
