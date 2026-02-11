import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart'; // Ensure csv: ^6.0.0 is in pubspec.yaml
import 'attendance_model.dart';

class DataProvider extends ChangeNotifier {
  Box<AttendanceLog>? _box;
  bool _isLoading = false;

  bool get isLoading => _isLoading;

  // --- 1. INIT DB ---
  Future<void> initDB() async {
    _box = await Hive.openBox<AttendanceLog>('attendance_logs');
    notifyListeners();
  }

  // --- 2. GET LOGS FOR DATE ---
  List<AttendanceLog> getLogsForDate(DateTime date) {
    if (_box == null) return [];

    final logs = _box!.values.where((l) =>
    l.logDate.year == date.year &&
        l.logDate.month == date.month &&
        l.logDate.day == date.day
    ).toList();

    logs.sort((a, b) {
      if (a.status == "Absent" && b.status != "Absent") return 1;
      if (a.status != "Absent" && b.status == "Absent") return -1;
      return a.entryTime.compareTo(b.entryTime);
    });

    return logs;
  }

  // --- 3. GET ACTIVE DATES ---
  List<DateTime> getActiveDates() {
    if (_box == null) return [];
    final uniqueDates = _box!.values.map((e) =>
        DateTime(e.logDate.year, e.logDate.month, e.logDate.day)
    ).toSet().toList();
    uniqueDates.sort((a, b) => b.compareTo(a));
    return uniqueDates;
  }

  // --- 4. STATS ---
  Map<String, double> getStatusDistribution(List<AttendanceLog> logs) {
    int onTime = 0, late = 0, absent = 0, replaced = 0;
    for (var log in logs) {
      String statusLower = log.status.toLowerCase();
      if (statusLower.contains("absent")) {
        absent++;
      } else {
        if (statusLower.contains("replaced")) replaced++;
        if (statusLower.contains("late")) late++;
        else onTime++;
      }
    }
    return {
      'On Time': onTime.toDouble(),
      'Late': late.toDouble(),
      'Absent': absent.toDouble(),
      'Replaced': replaced.toDouble(),
    };
  }

  // --- 5. PROCESS FILES (FINAL FIX) ---
  Future<String> processFiles(List<File> files, DateTime selectedDate) async {
    _isLoading = true;
    notifyListeners();

    int totalProcessed = 0;
    int errorCount = 0;
    Map<String, AttendanceLog> batchMap = {};

    try {
      for (var file in files) {
        final input = await file.readAsString();

        // UNIVERSAL NEWLINE FIX:
        // Some CSVs use \r, some \n. We let the converter detect it.
        // If it fails (rows.length == 1), we force it.
        var converter = const CsvToListConverter();
        List<List<dynamic>> rows = converter.convert(input);

        // Fallback for weird Excel formats (Mac/Old Windows)
        if (rows.length <= 1 && input.contains('\r')) {
          rows = converter.convert(input, eol: '\r');
        }
        if (rows.length <= 1 && input.contains('\n')) {
          rows = converter.convert(input, eol: '\n');
        }

        if (rows.isEmpty) continue;

        // --- STEP A: FIND HEADER ROW ---
        int headerIndex = -1;
        for (int i = 0; i < rows.length; i++) {
          String rowStr = rows[i].join(',').toLowerCase();
          // Fuzzy match to find the header row
          if (rowStr.contains("staff") && rowStr.contains("id")) {
            headerIndex = i;
            break;
          }
        }

        if (headerIndex == -1) {
          print("Skipping ${file.path}: No valid header found.");
          errorCount++;
          continue;
        }

        // --- STEP B: MAP COLUMNS ---
        List<String> header = rows[headerIndex].map((e) => e.toString().trim().toLowerCase()).toList();

        // FUZZY MATCHING (Fixes the BOM/Hidden character issue)
        int idIdx = header.indexWhere((h) => h.contains("staff") && h.contains("id"));
        int nameIdx = header.indexWhere((h) => h.contains("staff") && h.contains("name"));
        int statusIdx = header.indexWhere((h) => h.contains("status"));
        int timeIdx = header.indexWhere((h) => h.contains("time"));
        int hallIdx = header.indexWhere((h) => h.contains("hall"));

        if (idIdx == -1 || nameIdx == -1 || statusIdx == -1) {
          errorCount++;
          continue;
        }

        // --- STEP C: PROCESS DATA ---
        for (int i = headerIndex + 1; i < rows.length; i++) {
          var row = rows[i];
          if (row.length <= statusIdx) continue; // Skip incomplete rows

          String id = row[idIdx].toString().trim();
          String name = row[nameIdx].toString().trim();
          String status = row[statusIdx].toString().trim();
          String hall = (hallIdx != -1 && row.length > hallIdx) ? row[hallIdx].toString().trim() : "--";
          String timeStr = (timeIdx != -1 && row.length > timeIdx) ? row[timeIdx].toString().trim() : "--";

          if (id.isEmpty || name.isEmpty) continue;

          // TIME PARSING
          DateTime entryTime;
          if (status.toUpperCase().contains("ABSENT") || timeStr == "--" || timeStr.isEmpty) {
            entryTime = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, 0, 0);
          } else {
            entryTime = _parseFlexibleTime(selectedDate, timeStr) ??
                DateTime(selectedDate.year, selectedDate.month, selectedDate.day, 0, 0);
          }

          if (name.contains("(Rep")) {
            status = "Replaced - $status";
          }

          final log = AttendanceLog(
            staffId: id,
            name: name,
            hall: hall, // Ensure your AttendanceLog model has 'hall'
            entryTime: entryTime,
            status: status,
            logDate: DateTime(selectedDate.year, selectedDate.month, selectedDate.day),
          );

          // deduplication logic: prefer Present over Absent
          if (batchMap.containsKey(id)) {
            if (batchMap[id]!.status.contains("Absent") && !status.contains("Absent")) {
              batchMap[id] = log;
            }
          } else {
            batchMap[id] = log;
          }
        }
      }

      // --- SAVE TO DATABASE ---
      for (var log in batchMap.values) {
        final key = "${DateFormat('yyyyMMdd').format(selectedDate)}_${log.staffId}";
        await _box!.put(key, log);
        totalProcessed++;
      }

      _isLoading = false;
      notifyListeners();
      return "Success! Processed $totalProcessed records. (Errors/Skips: $errorCount)";

    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return "Error: $e";
    }
  }

  // --- TIME PARSER HELPER ---
  DateTime? _parseFlexibleTime(DateTime date, String timeStr) {
    try {
      // Clean up string "11/2 7:44:10 AM" -> "7:44:10 AM"
      String cleanTime = timeStr.trim();
      if (cleanTime.contains(' ')) {
        List<String> parts = cleanTime.split(' ');
        if (parts.length > 2) {
          // If format is "Date Time AM/PM" -> take the last 2 parts "7:44:10 AM"
          cleanTime = "${parts[parts.length-2]} ${parts[parts.length-1]}";
        }
      }

      try {
        DateTime t = DateFormat("h:mm:ss a").parse(cleanTime);
        return DateTime(date.year, date.month, date.day, t.hour, t.minute, t.second);
      } catch (_) {
        DateTime t = DateFormat("h:mm a").parse(cleanTime);
        return DateTime(date.year, date.month, date.day, t.hour, t.minute, 0);
      }
    } catch (e) {
      return null;
    }
  }

  Future<void> deleteRecordsForDate(DateTime date) async {
    if (_box == null) return;
    final keys = _box!.keys.where((k) => k.toString().startsWith(DateFormat('yyyyMMdd').format(date))).toList();
    await _box!.deleteAll(keys);
    notifyListeners();
  }

  Future<void> clearAllData() async {
    await _box?.clear();
    notifyListeners();
  }
}