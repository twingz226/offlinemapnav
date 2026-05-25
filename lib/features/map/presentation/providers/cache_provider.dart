import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/tile_cache_service.dart';

class CacheState {
  final int tileCount;
  final double sizeInKiB;
  final bool isLoading;

  CacheState({
    this.tileCount = 0,
    this.sizeInKiB = 0.0,
    this.isLoading = false,
  });

  String get formattedSize {
    if (sizeInKiB < 1024) {
      return '${sizeInKiB.toStringAsFixed(1)} KiB';
    }
    final sizeInMiB = sizeInKiB / 1024;
    return '${sizeInMiB.toStringAsFixed(1)} MiB';
  }
}

class CacheNotifier extends StateNotifier<CacheState> {
  CacheNotifier() : super(CacheState()) {
    loadStats();
  }

  final _service = TileCacheService();

  Future<void> loadStats() async {
    state = CacheState(
      tileCount: state.tileCount,
      sizeInKiB: state.sizeInKiB,
      isLoading: true,
    );
    try {
      final storeStats = _service.store.stats;
      final count = await storeStats.length;
      final size = await storeStats.size;
      state = CacheState(
        tileCount: count,
        sizeInKiB: size,
        isLoading: false,
      );
    } catch (e) {
      state = CacheState(
        tileCount: 0,
        sizeInKiB: 0.0,
        isLoading: false,
      );
    }
  }

  Future<void> clearCache() async {
    state = CacheState(
      tileCount: state.tileCount,
      sizeInKiB: state.sizeInKiB,
      isLoading: true,
    );
    try {
      await _service.clearCache();
    } catch (_) {}
    await loadStats();
  }
}

final cacheProvider = StateNotifierProvider<CacheNotifier, CacheState>((ref) {
  return CacheNotifier();
});
