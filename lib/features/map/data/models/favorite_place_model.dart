import 'package:hive/hive.dart';

part 'favorite_place_model.g.dart';

@HiveType(typeId: 1)
class FavoritePlaceModel extends HiveObject {

  @HiveField(0)
  String name;

  @HiveField(1)
  double latitude;

  @HiveField(2)
  double longitude;

  @HiveField(3)
  String description;

  FavoritePlaceModel({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.description,
  });
}
