import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'app.dart';
import 'core/theme/theme_provider.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

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

  runApp(
    ProviderScope(
      overrides: [
        themeProvider.overrideWith((ref) => initialTheme),
      ],
      child: const OfflineNavigatorApp(),
    ),
  );
}
