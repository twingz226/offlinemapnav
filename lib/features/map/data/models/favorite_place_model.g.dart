// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite_place_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FavoritePlaceModelAdapter extends TypeAdapter<FavoritePlaceModel> {
  @override
  final int typeId = 1;

  @override
  FavoritePlaceModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FavoritePlaceModel(
      name: fields[0] as String,
      latitude: fields[1] as double,
      longitude: fields[2] as double,
      description: fields[3] as String,
    );
  }

  @override
  void write(BinaryWriter writer, FavoritePlaceModel obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.latitude)
      ..writeByte(2)
      ..write(obj.longitude)
      ..writeByte(3)
      ..write(obj.description);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavoritePlaceModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
