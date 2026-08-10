import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json_helpers.dart';

/// يقابل `room` في json_schema.md.
class Room extends Equatable {
  const Room({
    this.name = '',
    this.widthM = 0,
    this.lengthM = 0,
    this.heightM = 0,
    this.roomType = RoomType.other,
  });

  final String name;
  final double widthM;
  final double lengthM;
  final double heightM;
  final RoomType roomType;

  double get areaM2 => widthM * lengthM;

  factory Room.fromJson(Map<String, dynamic> json) => Room(
        name: asString(json['name']),
        widthM: asDouble(json['width_m']),
        lengthM: asDouble(json['length_m']),
        heightM: asDouble(json['height_m']),
        roomType: RoomType.fromWire(json['room_type']),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'width_m': widthM,
        'length_m': lengthM,
        'height_m': heightM,
        'room_type': roomType.wire,
      };

  Room copyWith({
    String? name,
    double? widthM,
    double? lengthM,
    double? heightM,
    RoomType? roomType,
  }) =>
      Room(
        name: name ?? this.name,
        widthM: widthM ?? this.widthM,
        lengthM: lengthM ?? this.lengthM,
        heightM: heightM ?? this.heightM,
        roomType: roomType ?? this.roomType,
      );

  @override
  List<Object?> get props => [name, widthM, lengthM, heightM, roomType];
}
