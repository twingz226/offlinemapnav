import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/favorite_place_model.dart';
import '../../data/repositories/favorites_repository.dart';

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier,
        List<FavoritePlaceModel>>(
  (ref) => FavoritesNotifier(),
);

class FavoritesNotifier
    extends StateNotifier<List<FavoritePlaceModel>> {

  FavoritesNotifier() : super([]) {
    loadFavorites();
  }

  final _repo = FavoritesRepository();

  void loadFavorites() {
    state = _repo.getFavorites();
  }

  Future<void> addFavorite(
    FavoritePlaceModel place,
  ) async {

    await _repo.addFavorite(place);

    loadFavorites();
  }

  Future<void> removeFavorite(int index) async {

    await _repo.removeFavorite(index);

    loadFavorites();
  }
}
