import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import '../../../core/constants/tile_config.dart';

class TileDownloadService {
  final store = const FMTCStore(TileConfig.storeName);

  /// Track the active instance ID so we can cancel before re-downloading.
  String? _activeInstanceId;

  /// Cancel any in-progress download for [instanceId].
  /// Safe to call even if no download is running.
  Future<void> cancelDownload(String instanceId) async {
    try {
      await store.download.cancel(instanceId: instanceId);
    } catch (e) {
      debugPrint('Cancel download ($instanceId): $e');
    }
    if (_activeInstanceId == instanceId) {
      _activeInstanceId = null;
    }
  }

  Future<void> downloadRegion({
    required String regionName,
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required Function(double progress) onProgress,
    Function(DownloadProgress progressDetails)? onProgressDetails,
    bool skipExistingTiles = true,
  }) async {
    // Cancel any previously running download with the same instanceId to avoid
    // the "A download instance with ID … already exists" error.
    await cancelDownload(regionName);

    final region = RectangleRegion(bounds).toDownloadable(
      minZoom: minZoom,
      maxZoom: maxZoom,
      options: TileLayer(
        urlTemplate: TileConfig.urlTemplate,
        userAgentPackageName: 'com.offlinenavigator.app',
      ),
    );

    _activeInstanceId = regionName;

    final downloadStream = store.download.startForeground(
      region: region,
      instanceId: regionName,
      skipExistingTiles: skipExistingTiles,
    );

    await for (final event in downloadStream) {
      final progress = event.percentageProgress;
      onProgress(progress);
      if (onProgressDetails != null) {
        onProgressDetails(event);
      }
    }

    _activeInstanceId = null;
  }

  /// Delete all cached tiles from the store. Returns true if successful.
  Future<bool> deleteAllTiles() async {
    try {
      if (_activeInstanceId != null) {
        await cancelDownload(_activeInstanceId!);
      }
      if (await store.manage.ready) {
        await store.manage.reset();
      }
      return true;
    } catch (e) {
      debugPrint('Failed to delete tiles: $e');
      return false;
    }
  }

  /// Get the current tile count in the store.
  Future<int> getTileCount() async {
    try {
      return await store.stats.length;
    } catch (e) {
      debugPrint('Failed to get tile count: $e');
      return 0;
    }
  }

  /// Get the current cache size in KiB.
  Future<double> getCacheSizeKiB() async {
    try {
      return await store.stats.size;
    } catch (e) {
      debugPrint('Failed to get cache size: $e');
      return 0.0;
    }
  }
}
