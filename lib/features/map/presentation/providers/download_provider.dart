import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/tile_download_service.dart';

/// Represents a downloadable map region.
class DownloadableRegion {
  final String id;
  final String name;
  final LatLngBounds bounds;
  final int minZoom;
  final int maxZoom;

  const DownloadableRegion({
    required this.id,
    required this.name,
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
  });
}

/// Possible states for a download.
enum DownloadStatus {
  idle,       // Not started / never downloaded
  downloading,
  completed,
  error,
}

/// State representing a region download.
class DownloadState {
  final DownloadStatus status;
  final double progress; // 0.0 – 100.0
  final int tileCount;
  final double sizeKiB;
  final String? errorMessage;

  const DownloadState({
    this.status = DownloadStatus.idle,
    this.progress = 0.0,
    this.tileCount = 0,
    this.sizeKiB = 0.0,
    this.errorMessage,
  });

  DownloadState copyWith({
    DownloadStatus? status,
    double? progress,
    int? tileCount,
    double? sizeKiB,
    String? errorMessage,
  }) {
    return DownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      tileCount: tileCount ?? this.tileCount,
      sizeKiB: sizeKiB ?? this.sizeKiB,
      errorMessage: errorMessage,
    );
  }

  String get formattedSize {
    if (sizeKiB < 1024) {
      return '${sizeKiB.toStringAsFixed(1)} KiB';
    }
    final sizeInMiB = sizeKiB / 1024;
    if (sizeInMiB < 1024) {
      return '${sizeInMiB.toStringAsFixed(1)} MiB';
    }
    final sizeInGiB = sizeInMiB / 1024;
    return '${sizeInGiB.toStringAsFixed(2)} GiB';
  }
}

/// Pre-defined downloadable regions.
final availableRegions = [
  DownloadableRegion(
    id: 'dumaguete_region',
    name: 'Dumaguete Region',
    bounds: LatLngBounds(
      const LatLng(9.25, 123.26),
      const LatLng(9.36, 123.36),
    ),
    minZoom: 8,
    maxZoom: 17,
  ),
];

class DownloadNotifier extends StateNotifier<DownloadState> {
  DownloadNotifier() : super(const DownloadState()) {
    // Check if tiles already exist in the store on initialization
    _checkExistingTiles();
  }

  final _service = TileDownloadService();

  Future<void> _checkExistingTiles() async {
    final count = await _service.getTileCount();
    final size = await _service.getCacheSizeKiB();
    if (count > 0) {
      state = DownloadState(
        status: DownloadStatus.completed,
        progress: 100.0,
        tileCount: count,
        sizeKiB: size,
      );
    }
  }

  Future<void> startDownload(DownloadableRegion region) async {
    state = const DownloadState(
      status: DownloadStatus.downloading,
      progress: 0.1,
    );

    try {
      await _service.downloadRegion(
        regionName: region.id,
        bounds: region.bounds,
        minZoom: region.minZoom,
        maxZoom: region.maxZoom,
        onProgress: (progress) {
          state = state.copyWith(
            progress: progress,
          );
        },
      );

      // Download finished — fetch real stats
      final count = await _service.getTileCount();
      final size = await _service.getCacheSizeKiB();

      state = DownloadState(
        status: DownloadStatus.completed,
        progress: 100.0,
        tileCount: count,
        sizeKiB: size,
      );
    } catch (e) {
      debugPrint('Download failed: $e');
      // Still check if partial tiles were cached
      final count = await _service.getTileCount();
      final size = await _service.getCacheSizeKiB();

      state = DownloadState(
        status: DownloadStatus.error,
        progress: state.progress,
        tileCount: count,
        sizeKiB: size,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> deleteDownload() async {
    final success = await _service.deleteAllTiles();
    if (success) {
      state = const DownloadState(
        status: DownloadStatus.idle,
        progress: 0.0,
        tileCount: 0,
        sizeKiB: 0.0,
      );
    }
  }

  Future<void> refreshStats() async {
    final count = await _service.getTileCount();
    final size = await _service.getCacheSizeKiB();
    if (count > 0 && state.status == DownloadStatus.idle) {
      state = DownloadState(
        status: DownloadStatus.completed,
        progress: 100.0,
        tileCount: count,
        sizeKiB: size,
      );
    } else {
      state = state.copyWith(
        tileCount: count,
        sizeKiB: size,
      );
    }
  }
}

final downloadProvider =
    StateNotifierProvider<DownloadNotifier, DownloadState>(
  (ref) => DownloadNotifier(),
);
