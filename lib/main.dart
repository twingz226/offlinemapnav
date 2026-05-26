import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/constants/tile_config.dart';
import 'core/theme/theme_provider.dart';
import 'features/map/data/models/favorite_place_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load theme preference
  final prefs = await SharedPreferences.getInstance();
  final String? savedTheme = prefs.getString('theme_mode');
  ThemeMode initialTheme = ThemeMode.light; // default to Light Mode when launched for the first time
  if (savedTheme != null) {
    if (savedTheme == 'dark') {
      initialTheme = ThemeMode.dark;
    } else if (savedTheme == 'light') {
      initialTheme = ThemeMode.light;
    } else if (savedTheme == 'system') {
      initialTheme = ThemeMode.system;
    }
  }

  // Hive
  await Hive.initFlutter();
  Hive.registerAdapter(FavoritePlaceModelAdapter());
  await Hive.openBox<FavoritePlaceModel>('favoritesBox');
  await Hive.openBox('routesCache');
  await Hive.openBox('routesHistory');
  await Hive.openBox('osm_graphs');

  // Offline tile cache
  await FMTCObjectBoxBackend().initialise();

  // Create the tile store if it doesn't exist yet.
  // We do NOT reset it — that would wipe all downloaded offline map data.
  final store = const FMTCStore(TileConfig.storeName);
  if (!await store.manage.ready) {
    await store.manage.create();
  }

  runApp(
    ProviderScope(
      overrides: [
        themeProvider.overrideWith((ref) => initialTheme),
      ],
      child: const OfflineNavigatorApp(),
    ),
  );
}
