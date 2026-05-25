import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

import '../../services/tile_download_service.dart';

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
  Timer? _debounceTimer;
  Timer? _completedDismissTimer;
  LatLngBounds? _lastDownloadedBounds;
  bool _isDownloading = false;
  String _currentInstanceId = '';

  /// Called whenever the visible map viewport changes.
  /// Debounces the call to avoid spamming downloads on every pixel pan.
  void onMapPositionChanged(LatLngBounds visibleBounds, double zoom) {
    if (_isDownloading || state.status == AutoDownloadStatus.prompting) return; // Don't interrupt download or active prompt

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1200), () {
      _evaluateAndDownload(visibleBounds, zoom);
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

    // Calculate rough distance between centers
    const distance = Distance();
    final dist = distance.as(LengthUnit.Kilometer, lastCenter, newCenter);

    // Trigger new download if moved more than 0.5km
    return dist > 0.5;
  }

  /// Evaluate whether to auto-download the current viewport.
  Future<void> _evaluateAndDownload(LatLngBounds bounds, double zoom) async {
    // Skip if this area was recently downloaded
    if (!_isNewArea(bounds)) return;

    // Check connectivity
    bool isOnline = false;
    try {
      final results = await Connectivity().checkConnectivity();
      isOnline = !results.contains(ConnectivityResult.none);
    } catch (_) {}

    if (!isOnline) {
      // We're offline — don't try to download
      return;
    }

    // Instead of downloading directly, show the confirmation prompt overlay
    final centerLat = (bounds.north + bounds.south) / 2;
    final centerLng = (bounds.east + bounds.west) / 2;
    final label = '${centerLat.toStringAsFixed(2)}°, ${centerLng.toStringAsFixed(2)}°';

    state = AutoDownloadState(
      status: AutoDownloadStatus.prompting,
      regionLabel: label,
      pendingBounds: bounds,
      pendingZoom: zoom,
      dismissed: false,
    );
  }

  /// User confirmed the download.
  Future<void> confirmDownload() async {
    if (state.pendingBounds == null || state.pendingZoom == null) return;
    final bounds = state.pendingBounds!;
    final zoom = state.pendingZoom!;

    // Move to idle briefly to let overlay handle animation transitions cleanly,
    // then invoke downloadViewport.
    state = state.copyWith(
      status: AutoDownloadStatus.idle,
      pendingBounds: null,
      pendingZoom: null,
    );

    await _downloadViewport(bounds, zoom);
  }

  /// User rejected the download.
  void rejectDownload() {
    if (state.pendingBounds != null) {
      // Register this bounds as "handled" so we don't prompt again immediately
      _lastDownloadedBounds = state.pendingBounds;
    }

    state = const AutoDownloadState(
      status: AutoDownloadStatus.idle,
      dismissed: true,
    );
  }

  /// Download tiles for the given viewport bounds.
  Future<void> _downloadViewport(LatLngBounds bounds, double zoom) async {
    if (_isDownloading) return;
    _isDownloading = true;

    // Calculate zoom range: current zoom ± 2 levels, clamped
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

    // Generate a unique instance ID for this download
    _currentInstanceId = 'auto_${DateTime.now().millisecondsSinceEpoch}';

    // Generate a human-readable label
    final centerLat = (bounds.north + bounds.south) / 2;
    final centerLng = (bounds.east + bounds.west) / 2;
    final label = '${centerLat.toStringAsFixed(2)}°, ${centerLng.toStringAsFixed(2)}°';

    state = AutoDownloadState(
      status: AutoDownloadStatus.downloading,
      progress: 0.0,
      regionLabel: label,
      dismissed: false,
      hasNewTiles: false,
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
          );

          // Auto-dismiss the completed notification after 4 seconds
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
          // No new tiles downloaded, everything was already stored offline.
          // Silently complete and reset to idle.
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

        // Auto-dismiss error after 5 seconds
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
