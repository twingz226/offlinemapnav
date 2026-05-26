import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/map/presentation/pages/splash_page.dart';

class OfflineNavigatorApp extends ConsumerWidget {
  const OfflineNavigatorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    // Save theme selection when it changes
    ref.listen<ThemeMode>(themeProvider, (previous, next) async {
      final prefs = await SharedPreferences.getInstance();
      String modeStr = 'light';
      if (next == ThemeMode.dark) {
        modeStr = 'dark';
      } else if (next == ThemeMode.system) {
        modeStr = 'system';
      }
      await prefs.setString('theme_mode', modeStr);
    });

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const SplashPage(),
    );
  }
}
