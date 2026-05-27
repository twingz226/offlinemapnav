import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart' hide DownloadableRegion;
import 'package:hive/hive.dart';

import '../../services/tile_download_service.dart';
import '../../services/osm_graph_service.dart';
import '../../services/administrative_boundary_service.dart';
import 'download_provider.dart';
import '../../data/models/place_boundary.dart';

/// Status of the auto-download process.
enum AutoDownloadStatus {
  idle,
  checking,
  prompting,
  downloading,
  completed,
  error,
  offline,
}

/// State for the auto-download system.
class AutoDownloadState {
  final AutoDownloadStatus status;
  final double progress; // 0.0 – 100.0
  final String? regionLabel;
  final String? errorMessage;
  final int tilesDownloaded;
  final DateTime? lastCompletedAt;
  final bool dismissed; // user dismissed the popup
  final bool hasNewTiles; // true if any tiles were actually downloaded (not skipped)
  final LatLngBounds? pendingBounds;
  final double? pendingZoom;
  final List<PlaceBoundary>? suggestedPlaces; // detected admin places
  final PlaceBoundary? detectedPlace; // the specific city detected at user location

  const AutoDownloadState({
    this.status = AutoDownloadStatus.idle,
    this.progress = 0.0,
    this.regionLabel,
    this.errorMessage,
    this.tilesDownloaded = 0,
    this.lastCompletedAt,
    this.dismissed = false,
    this.hasNewTiles = false,
    this.pendingBounds,
    this.pendingZoom,
    this.suggestedPlaces,
    this.detectedPlace,
  });

  AutoDownloadState copyWith({
    AutoDownloadStatus? status,
    double? progress,
    String? regionLabel,
    String? errorMessage,
    int? tilesDownloaded,
    DateTime? lastCompletedAt,
    bool? dismissed,
    bool? hasNewTiles,
    LatLngBounds? pendingBounds,
    double? pendingZoom,
    List<PlaceBoundary>? suggestedPlaces,
    PlaceBoundary? detectedPlace,
  }) {
    return AutoDownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      regionLabel: regionLabel ?? this.regionLabel,
      errorMessage: errorMessage,
      tilesDownloaded: tilesDownloaded ?? this.tilesDownloaded,
      lastCompletedAt: lastCompletedAt ?? this.lastCompletedAt,
      dismissed: dismissed ?? this.dismissed,
      hasNewTiles: hasNewTiles ?? this.hasNewTiles,
      pendingBounds: pendingBounds ?? this.pendingBounds,
      pendingZoom: pendingZoom ?? this.pendingZoom,
      suggestedPlaces: suggestedPlaces ?? this.suggestedPlaces,
      detectedPlace: detectedPlace ?? this.detectedPlace,
    );
  }

  bool get isActive =>
      status == AutoDownloadStatus.downloading ||
      status == AutoDownloadStatus.checking ||
      status == AutoDownloadStatus.prompting;
  
  bool get shouldShowOverlay =>
      !dismissed &&
      (status == AutoDownloadStatus.prompting ||
       (hasNewTiles &&
        (status == AutoDownloadStatus.downloading ||
         status == AutoDownloadStatus.completed ||
         status == AutoDownloadStatus.error)));
}

class AutoDownloadNotifier extends StateNotifier<AutoDownloadState> {
  AutoDownloadNotifier() : super(const AutoDownloadState());

  final _service = TileDownloadService();
  final _graphService = OSMGraphService();
  final _boundaryService = AdministrativeBoundaryService();
  Timer? _debounceTimer;
  Timer? _completedDismissTimer;
  LatLngBounds? _lastDownloadedBounds;
  bool _isDownloading = false;
  String _currentInstanceId = '';
  String? _lastCheckedPlaceId; // avoid re-prompting the same place repeatedly

  /// Check if a place has already been downloaded (persisted in Hive).
  bool _isPlaceDownloaded(String placeId) {
    try {
      final box = Hive.box('downloaded_places');
      return box.containsKey(placeId);
    } catch (e) {
      debugPrint('Error checking downloaded places: $e');
      return false;
    }
  }

  /// Mark a place as downloaded in Hive persistence.
  Future<void> _markPlaceDownloaded(PlaceBoundary place) async {
    try {
      final box = Hive.box('downloaded_places');
      await box.put(place.id, {
        'name': place.name,
        'south': place.bounds.south,
        'west': place.bounds.west,
        'north': place.bounds.north,
        'east': place.bounds.east,
        'downloadedAt': DateTime.now().toIso8601String(),
      });
      debugPrint('✅ Marked place as downloaded: ${place.name} (${place.id})');
    } catch (e) {
      debugPrint('Error marking place as downloaded: $e');
    }
  }

  /// Called when the user's GPS location changes. Detects the city/municipality
  /// at the user's current location and prompts to download if not yet cached.
  Future<void> checkCurrentLocation(double lat, double lng, {double zoom = 15}) async {
    // Don't interrupt ongoing downloads or active prompts
    if (_isDownloading || state.status == AutoDownloadStatus.prompting) return;
    if (state.status == AutoDownloadStatus.downloading) return;

    // Check connectivity first
    bool isOnline = false;
    try {
      final results = await Connectivity().checkConnectivity();
      isOnline = !results.contains(ConnectivityResult.none);
    } catch (_) {}
    if (!isOnline) return;

    // Reverse-geocode the user's location to find their city
    final place = await _boundaryService.getPlaceForLocation(lat, lng);
    if (place == null) return;

    // Skip if we already checked this place recently (avoid spam)
    if (_lastCheckedPlaceId == place.id) return;
    _lastCheckedPlaceId = place.id;

    // Skip if already downloaded
    if (_isPlaceDownloaded(place.id)) {
      debugPrint('📦 ${place.name} already downloaded, skipping prompt');
      return;
    }

    debugPrint('🏙️ User is in ${place.name} — not yet downloaded, prompting...');

    // Show prompt for this specific city
    if (mounted) {
      state = AutoDownloadState(
        status: AutoDownloadStatus.prompting,
        regionLabel: place.name,
        pendingBounds: place.bounds,
        pendingZoom: zoom,
        detectedPlace: place,
        suggestedPlaces: [place],
        dismissed: false,
      );
    }
  }

  /// Called whenever the visible map viewport changes.
  /// Debounces the call to avoid spamming downloads on every pixel pan.
  void onMapPositionChanged(LatLngBounds visibleBounds, double zoom) {
    if (_isDownloading || state.status == AutoDownloadStatus.prompting) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1500), () async {
      await _evaluateViewport(visibleBounds, zoom);
    });
  }

  /// Check if the viewport is significantly different from the last downloaded area.
  bool _isNewArea(LatLngBounds bounds) {
    if (_lastDownloadedBounds == null) return true;

    final lastCenter = LatLng(
      (_lastDownloadedBounds!.north + _lastDownloadedBounds!.south) / 2,
      (_lastDownloadedBounds!.east + _lastDownloadedBounds!.west) / 2,
    );
    final newCenter = LatLng(
      (bounds.north + bounds.south) / 2,
      (bounds.east + bounds.west) / 2,
    );

    const distance = Distance();
    final dist = distance.as(LengthUnit.Kilometer, lastCenter, newCenter);

    return dist > 0.5;
  }

  /// Evaluate the current viewport: detect cities inside it and prompt if needed.
  Future<void> _evaluateViewport(LatLngBounds bounds, double zoom) async {
    if (!_isNewArea(bounds)) return;

    // Check connectivity
    bool isOnline = false;
    try {
      final results = await Connectivity().checkConnectivity();
      isOnline = !results.contains(ConnectivityResult.none);
    } catch (_) {}
    if (!isOnline) return;

    // Detect the city at the center of the viewport
    final centerLat = (bounds.north + bounds.south) / 2;
    final centerLng = (bounds.east + bounds.west) / 2;
    final place = await _boundaryService.getPlaceForLocation(centerLat, centerLng);

    if (place != null && !_isPlaceDownloaded(place.id)) {
      // Prompt for this city
      if (mounted) {
        state = AutoDownloadState(
          status: AutoDownloadStatus.prompting,
          regionLabel: place.name,
          pendingBounds: place.bounds,
          pendingZoom: zoom,
          detectedPlace: place,
          suggestedPlaces: [place],
          dismissed: false,
        );
      }
    }
  }

  /// User confirmed the download (generic "Download" button).
  Future<void> confirmDownload() async {
    final place = state.detectedPlace;
    final bounds = place?.bounds ?? state.pendingBounds;
    final zoom = state.pendingZoom ?? 15;

    if (bounds == null) return;

    state = state.copyWith(
      status: AutoDownloadStatus.idle,
      pendingBounds: null,
      pendingZoom: null,
      suggestedPlaces: null,
    );

    await _downloadViewport(bounds, zoom, place: place);
  }

  /// Confirm download for a specific place.
  Future<void> confirmPlaceDownload(PlaceBoundary place) async {
    final zoom = state.pendingZoom ?? 15;

    state = state.copyWith(
      status: AutoDownloadStatus.idle,
      pendingBounds: null,
      pendingZoom: null,
      suggestedPlaces: null,
    );

    await _downloadViewport(place.bounds, zoom, place: place);
  }

  /// User rejected the download.
  void rejectDownload() {
    if (state.pendingBounds != null) {
      _lastDownloadedBounds = state.pendingBounds;
    }
    // Mark the place so we don't prompt again this session
    if (state.detectedPlace != null) {
      _lastCheckedPlaceId = state.detectedPlace!.id;
    }

    state = const AutoDownloadState(
      status: AutoDownloadStatus.idle,
      dismissed: true,
    );
  }

  /// Download tiles for the given bounds.
  Future<void> _downloadViewport(LatLngBounds bounds, double zoom, {PlaceBoundary? place}) async {
    if (_isDownloading) return;
    _isDownloading = true;

    final int currentZoom = zoom.round();
    final int minZoom = (currentZoom - 1).clamp(1, 18);
    final int maxZoom = (currentZoom + 2).clamp(1, 18);

    // Expand bounds slightly (~15%) for smoother UX at edges
    final latSpan = bounds.north - bounds.south;
    final lngSpan = bounds.east - bounds.west;
    final expandedBounds = LatLngBounds(
      LatLng(bounds.south - latSpan * 0.15, bounds.west - lngSpan * 0.15),
      LatLng(bounds.north + latSpan * 0.15, bounds.east + lngSpan * 0.15),
    );

    _currentInstanceId = place?.id ?? 'auto_${DateTime.now().millisecondsSinceEpoch}';

    final label = place?.name ?? '${((bounds.north + bounds.south) / 2).toStringAsFixed(2)}°, ${((bounds.east + bounds.west) / 2).toStringAsFixed(2)}°';

    state = AutoDownloadState(
      status: AutoDownloadStatus.downloading,
      progress: 0.0,
      regionLabel: label,
      dismissed: false,
      hasNewTiles: false,
      detectedPlace: place,
    );

    bool hasNewTiles = false;

    try {
      await _service.downloadRegion(
        regionName: _currentInstanceId,
        bounds: expandedBounds,
        minZoom: minZoom,
        maxZoom: maxZoom,
        skipExistingTiles: true,
        onProgress: (progress) {
          if (mounted) {
            state = state.copyWith(
              progress: progress,
            );
          }
        },
        onProgressDetails: (DownloadProgress details) {
          if (details.cachedTiles > 0 || details.failedTiles > 0) {
            hasNewTiles = true;
          }
          if (mounted) {
            state = state.copyWith(
              tilesDownloaded: details.cachedTiles,
              hasNewTiles: hasNewTiles,
            );
          }
        },
      );

      _lastDownloadedBounds = expandedBounds;

      // Mark this place as downloaded in persistence
      if (place != null) {
        await _markPlaceDownloaded(place);
      }

      // Compile OSM road graph for this viewport so offline routing can use it
      if (hasNewTiles) {
        try {
          debugPrint('AutoDownload: Compiling OSM road graph for: $label');
          final graphRegion = DownloadableRegion(
            id: _currentInstanceId,
            name: place != null ? place.name : 'Auto: $label',
            bounds: expandedBounds,
            minZoom: minZoom,
            maxZoom: maxZoom,
          );
          await _graphService.compileGraphForRegion(graphRegion);
          debugPrint('AutoDownload: OSM road graph compilation complete for $label');
        } catch (e) {
          debugPrint('AutoDownload: OSM graph compilation failed (non-fatal): $e');
        }
      }

      if (mounted) {
        if (hasNewTiles) {
          state = AutoDownloadState(
            status: AutoDownloadStatus.completed,
            progress: 100.0,
            regionLabel: label,
            tilesDownloaded: state.tilesDownloaded,
            lastCompletedAt: DateTime.now(),
            dismissed: false,
            hasNewTiles: true,
            detectedPlace: place,
          );

          _completedDismissTimer?.cancel();
          _completedDismissTimer = Timer(const Duration(seconds: 4), () {
            if (mounted && state.status == AutoDownloadStatus.completed) {
              state = state.copyWith(
                status: AutoDownloadStatus.idle,
                dismissed: true,
              );
            }
          });
        } else {
          state = const AutoDownloadState(
            status: AutoDownloadStatus.idle,
            dismissed: true,
            hasNewTiles: false,
          );
        }
      }
    } catch (e) {
      debugPrint('Auto-download failed: $e');
      if (mounted) {
        state = AutoDownloadState(
          status: AutoDownloadStatus.error,
          progress: state.progress,
          regionLabel: label,
          errorMessage: e.toString(),
          dismissed: false,
          hasNewTiles: hasNewTiles,
        );

        _completedDismissTimer?.cancel();
        _completedDismissTimer = Timer(const Duration(seconds: 5), () {
          if (mounted && state.status == AutoDownloadStatus.error) {
            state = state.copyWith(
              status: AutoDownloadStatus.idle,
              dismissed: true,
            );
          }
        });
      }
    } finally {
      _isDownloading = false;
    }
  }

  /// Dismiss the overlay popup manually.
  void dismiss() {
    state = state.copyWith(dismissed: true);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _completedDismissTimer?.cancel();
    super.dispose();
  }
}

final autoDownloadProvider =
    StateNotifierProvider<AutoDownloadNotifier, AutoDownloadState>(
  (ref) => AutoDownloadNotifier(),
);
