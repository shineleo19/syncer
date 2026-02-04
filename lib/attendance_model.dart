import 'package:hive/hive.dart'; // <--- THIS IS CRITICAL

part 'attendance_model.g.dart';

@HiveType(typeId: 0)
class AttendanceLog extends HiveObject {
  @HiveField(0)
  final String staffId;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String hall;

  @HiveField(3)
  final DateTime entryTime; // The earliest time for that day

  @HiveField(4)
  final String status; // "On Time" or "Late entry"

  @HiveField(5)
  final DateTime logDate; // The date assigned by the user

  AttendanceLog({
    required this.staffId,
    required this.name,
    required this.hall,
    required this.entryTime,
    required this.status,
    required this.logDate,
  });
}