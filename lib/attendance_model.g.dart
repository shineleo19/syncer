// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attendance_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AttendanceLogAdapter extends TypeAdapter<AttendanceLog> {
  @override
  final int typeId = 0;

  @override
  AttendanceLog read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AttendanceLog(
      staffId: fields[0] as String,
      name: fields[1] as String,
      hall: fields[2] as String,
      entryTime: fields[3] as DateTime,
      status: fields[4] as String,
      logDate: fields[5] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, AttendanceLog obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.staffId)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.hall)
      ..writeByte(3)
      ..write(obj.entryTime)
      ..writeByte(4)
      ..write(obj.status)
      ..writeByte(5)
      ..write(obj.logDate);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is AttendanceLogAdapter &&
              runtimeType == other.runtimeType &&
              typeId == other.typeId;
}
