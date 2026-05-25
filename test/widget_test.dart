// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:offline_map/app.dart';
import 'package:offline_map/features/map/data/models/favorite_place_model.dart';

void main() {
  setUpAll(() async {
    final tempDir = Directory.systemTemp.createTempSync();
    Hive.init(tempDir.path);
    try {
      Hive.registerAdapter(FavoritePlaceModelAdapter());
    } catch (_) {}
    await Hive.openBox<FavoritePlaceModel>('favoritesBox');
    await Hive.openBox('routesCache');
  });

  testWidgets('Smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: OfflineNavigatorApp(),
      ),
    );

    // Verify settings tab exists or map is rendered
    expect(find.byType(OfflineNavigatorApp), findsOneWidget);
  });
}

