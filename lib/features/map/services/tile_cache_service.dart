import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import '../../../core/constants/tile_config.dart';

class TileCacheService {
  final store = const FMTCStore(TileConfig.storeName);

  Future<void> createStore() async {
    await store.manage.create();
  }

  Future<double> getCacheSize() async {
    final stats = await store.stats.all;
    return stats.length.toDouble();
  }

  Future<void> clearCache() async {
    if (await store.manage.ready) {
      await store.manage.reset();
    } else {
      await store.manage.create();
    }
  }
}

