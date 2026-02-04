import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'attendance_model.dart';

class DataProvider extends ChangeNotifier {
  Box<AttendanceLog>? _box;
  bool _isLoading = false;

  bool get isLoading => _isLoading;

  // --- 1. GET ALL LOGS ---
  List<AttendanceLog> get allLogs {
    if (_box == null) return [];
    var list = _box!.values.toList();
    list.sort((a, b) {
      int dateComp = b.logDate.compareTo(a.logDate);
      if (dateComp != 0) return dateComp;
      return a.entryTime.compareTo(b.entryTime);
    });
    return list;
  }

  // --- 2. GET LOGS FOR DATE ---
  List<AttendanceLog> getLogsForDate(DateTime date) {
    if (_box == null) return [];
    return _box!.values.where((l) =>
    l.logDate.year == date.year &&
        l.logDate.month == date.month &&
        l.logDate.day == date.day
    ).toList()
      ..sort((a, b) => a.entryTime.compareTo(b.entryTime));
  }

  Future<void> initDB() async {
    _box = await Hive.openBox<AttendanceLog>('attendance_logs');
    notifyListeners();
  }

  // --- STATS (UPDATED: OVERLAPPING COUNTS) ---
  Map<String, double> getStatusDistribution(List<AttendanceLog> logs) {
    int late = 0, absent = 0, replaced = 0, onTime = 0;

    for (var e in logs) {
      String s = e.status.toLowerCase();

      // Absent is exclusive
      if (s.contains("absent")) {
        absent++;
      } else {
        // For present staff, check attributes independently

        // 1. Check Replacement
        if (s.contains("replaced")) {
          replaced++;
        }

        // 2. Check Punctuality (Counts for both Normal AND Replaced staff)
        if (s.contains("late")) {
          late++;
        } else {
          // If not absent and not late, they are On Time
          onTime++;
        }
      }
    }

    return {
      'On Time': onTime.toDouble(),
      'Late': late.toDouble(),
      'Absent': absent.toDouble(),
      'Replaced': replaced.toDouble(),
    };
  }

  int getTotalRecords(List<AttendanceLog> logs) {
    // Total Physical Scans (Present People)
    // Only exclude Absent. Replaced staff are physically present, so they count.
    return logs.where((e) => !e.status.toLowerCase().contains("absent")).length;
  }

  // --- PROCESS FILES (UPDATED STATUS STRING) ---
  Future<String> processFiles(List<File> files, DateTime selectedDate) async {
    _isLoading = true;
    notifyListeners();

    int addedCount = 0;
    int errorCount = 0;
    Map<String, AttendanceLog> batchMap = {};

    final replacementRegex = RegExp(r"(.*?)\(Rep\s+(.*?)\)");

    try {
      for (var file in files) {
        List<String> lines = await file.readAsLines();
        if (lines.isNotEmpty && lines[0].toLowerCase().contains("staff")) lines.removeAt(0);

        // --- PASS 1: COLLECT ABSENT IDs ---
        Map<String, String> nameToIdMap = {};
        for (var line in lines) {
          if (line.trim().isEmpty) continue;
          List<String> cols = line.split(',').map((e) => e.trim()).toList();
          if (cols.length < 6) continue;

          String id = cols[0];
          String name = cols[1];
          String hall = cols[3];
          String status = cols[5];

          if (status.toUpperCase() == "ABSENT") {
            nameToIdMap[name.toLowerCase()] = id;
            _addRecordToBatch(batchMap, AttendanceLog(
                staffId: id,
                name: name,
                hall: hall,
                entryTime: DateTime(selectedDate.year, selectedDate.month, selectedDate.day, 23, 59),
                status: "Absent",
                logDate: selectedDate
            ));
          }
        }

        // --- PASS 2: PROCESS REST ---
        for (var line in lines) {
          if (line.trim().isEmpty) continue;
          List<String> cols = line.split(',').map((e) => e.trim()).toList();
          if (cols.length < 6) { errorCount++; continue; }

          String rawId = cols[0];
          String rawName = cols[1];
          String hall = cols[3];
          String timeStr = cols[4];
          String status = cols[5];

          if (status.toUpperCase() == "ABSENT") continue;

          DateTime? entryTime = _parseFlexibleTime(selectedDate, timeStr);
          if (entryTime == null) { errorCount++; continue; }

          final match = replacementRegex.firstMatch(rawName);

          if (match != null) {
            String replacerName = match.group(1)?.trim() ?? "Unknown";
            String replacedName = match.group(2)?.trim() ?? "Unknown";
            String finalId = rawId;
            String finalName = replacedName;

            if (nameToIdMap.containsKey(replacedName.toLowerCase())) {
              finalId = nameToIdMap[replacedName.toLowerCase()]!;
            }

            // CRITICAL CHANGE: Append original status (Late/On Time) to the string
            // New Format: "Replaced by Arjun - LATE ENTRY"
            _addRecordToBatch(batchMap, AttendanceLog(
                staffId: finalId,
                name: finalName,
                hall: hall,
                entryTime: entryTime,
                status: "Replaced by $replacerName - $status",
                logDate: selectedDate
            ));

          } else {
            _addRecordToBatch(batchMap, AttendanceLog(
                staffId: rawId,
                name: rawName,
                hall: hall,
                entryTime: entryTime,
                status: status,
                logDate: selectedDate
            ));
          }
        }
      }

      for (var record in batchMap.values) {
        String dbKey = "${DateFormat('yyyyMMdd').format(selectedDate)}_${record.staffId}";
        await _box!.put(dbKey, record);
        addedCount++;
      }

      _isLoading = false;
      notifyListeners();
      return "Processed: $addedCount records updated. (Errors: $errorCount)";

    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return "Error: $e";
    }
  }

  void _addRecordToBatch(Map<String, AttendanceLog> map, AttendanceLog newRecord) {
    if (!map.containsKey(newRecord.staffId)) {
      map[newRecord.staffId] = newRecord;
      return;
    }
    AttendanceLog existingRecord = map[newRecord.staffId]!;
    bool isNewAbsent = newRecord.status.toLowerCase().contains("absent");
    bool isExistingAbsent = existingRecord.status.toLowerCase().contains("absent");

    if (isExistingAbsent && !isNewAbsent) {
      map[newRecord.staffId] = newRecord;
      return;
    }
    if (!isExistingAbsent && isNewAbsent) {
      return;
    }
    if (existingRecord.entryTime.isAfter(newRecord.entryTime)) {
      map[newRecord.staffId] = newRecord;
    }
  }

  Future<void> deleteRecordsForDate(DateTime date) async {
    if (_box == null) return;
    final keys = _box!.keys.where((k) => k.toString().startsWith(DateFormat('yyyyMMdd').format(date))).toList();
    await _box!.deleteAll(keys);
    notifyListeners();
  }

  List<DateTime> getActiveDates() {
    if (_box == null) return [];
    final dates = _box!.values.map((e) => e.logDate).toSet().toList();
    dates.sort((a, b) => b.compareTo(a));
    return dates;
  }

  Future<void> clearAllData() async {
    await _box?.clear();
    notifyListeners();
  }

  DateTime? _parseFlexibleTime(DateTime date, String timeStr) {
    if (timeStr == "--" || timeStr.isEmpty) return null;
    List<String> formats = [
      "d/M h:mm:ss a", "d/M h:mm a", "M/d h:mm:ss a",
      "h:mm a", "h:mm:ss a", "HH:mm", "H:mm"
    ];
    for (var fmt in formats) {
      try {
        DateFormat parser = DateFormat(fmt);
        DateTime t = parser.parse(timeStr);
        return DateTime(date.year, date.month, date.day, t.hour, t.minute, t.second);
      } catch (e) {}
    }
    return null;
  }
}