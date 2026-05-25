import '../datasources/local_storage_datasource.dart';
import '../models/favorite_place_model.dart';

class FavoritesRepository {

  final _local = LocalStorageDataSource();

  Future<void> addFavorite(
    FavoritePlaceModel place,
  ) async {
    await _local.saveFavorite(place);
  }

  List<FavoritePlaceModel> getFavorites() {
    return _local.getFavorites();
  }

  Future<void> removeFavorite(int index) async {
    await _local.deleteFavorite(index);
  }
}
