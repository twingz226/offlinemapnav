import 'package:hive/hive.dart';

import '../models/favorite_place_model.dart';

class LocalStorageDataSource {

  final Box<FavoritePlaceModel> favoritesBox =
      Hive.box<FavoritePlaceModel>('favoritesBox');

  Future<void> saveFavorite(
    FavoritePlaceModel place,
  ) async {
    await favoritesBox.add(place);
  }

  List<FavoritePlaceModel> getFavorites() {
    return favoritesBox.values.toList();
  }

  Future<void> deleteFavorite(int index) async {
    await favoritesBox.deleteAt(index);
  }
}
