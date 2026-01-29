import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(MergerApp());
}

class MergerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Exam Log Merger',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: MergerHome(),
    );
  }
}

class MergerHome extends StatefulWidget {
  @override
  _MergerHomeState createState() => _MergerHomeState();
}

class _MergerHomeState extends State<MergerHome> {
  // We use a Set to avoid duplicate file paths automatically
  final List<File> _selectedFiles = [];
  bool _isProcessing = false;

  // Stats for the UI
  int _mergedCount = 0;
  String? _lastSavedPath;

  // --- LOGIC: ADD FILES (Accumulative) ---
  void _addFiles() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result != null) {
      setState(() {
        for (var path in result.paths) {
          if (path != null) {
            File file = File(path);
            // Prevent adding the exact same file twice
            if (!_selectedFiles.any((f) => f.path == file.path)) {
              _selectedFiles.add(file);
            }
          }
        }
        // Reset success state when new files are added
        _mergedCount = 0;
        _lastSavedPath = null;
      });
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  void _clearAll() {
    setState(() {
      _selectedFiles.clear();
      _mergedCount = 0;
      _lastSavedPath = null;
    });
  }

  // --- LOGIC: MERGE PROCESS ---
  void _processFiles() async {
    if (_selectedFiles.isEmpty) return;
    setState(() { _isProcessing = true; });

    Map<String, AttendanceRecord> masterRecords = {};

    try {
      for (var file in _selectedFiles) {
        List<String> lines = await file.readAsLines();

        for (var line in lines) {
          if (line.toLowerCase().contains("staff id") || line.trim().isEmpty) continue;

          List<String> cols = line.split(',');
          if (cols.length < 4) continue;

          String id = cols[0].trim();
          String name = cols[1].trim();
          String hall = cols[2].trim();
          String timeStr = cols[3].trim();

          DateTime? timestamp = _parseDate(timeStr);

          if (timestamp != null) {
            var newRecord = AttendanceRecord(id, name, hall, timeStr, timestamp);

            // Logic: Only keep the EARLIEST time for this ID
            if (!masterRecords.containsKey(id)) {
              masterRecords[id] = newRecord;
            } else {
              // If existing record time is AFTER new record time, replace it
              if (masterRecords[id]!.rawTime.isAfter(timestamp)) {
                masterRecords[id] = newRecord;
              }
            }
          }
        }
      }

      await _saveMasterFile(masterRecords.values.toList());

    } catch (e) {
      _showErrorDialog(e.toString());
    } finally {
      setState(() { _isProcessing = false; });
    }
  }

  Future<void> _saveMasterFile(List<AttendanceRecord> finalStats) async {
    StringBuffer csv = StringBuffer();
    csv.writeln("Staff ID,Staff Name,Hall No,First Entry Time");

    // Sort by Hall Number for neatness
    finalStats.sort((a, b) => a.hall.compareTo(b.hall));

    for (var rec in finalStats) {
      csv.writeln("${rec.id},${rec.name},${rec.hall},${rec.originalTimeStr}");
    }

    String outputDir = (await getApplicationDocumentsDirectory()).path;
    String filename = "$outputDir/Master_Attendance_Consolidated.csv";
    File(filename).writeAsStringSync(csv.toString());

    setState(() {
      _mergedCount = finalStats.length;
      _lastSavedPath = filename;
    });

    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Successfully Saved to Documents!"),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        )
    );
  }

  DateTime? _parseDate(String dateStr) {
    try {
      int year = DateTime.now().year;
      String fullStr = "$year/$dateStr";
      DateFormat format = DateFormat("yyyy/d/M h:mm a");
      return format.parse(fullStr);
    } catch (e) {
      return null;
    }
  }

  void _showErrorDialog(String content) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text("Error"), content: Text(content), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: Text("OK"))],
    ));
  }

  // --- UI CONSTRUCTION ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Exam Log Merger", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        elevation: 4,
        actions: [
          if (_selectedFiles.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_sweep, color: Colors.white),
              tooltip: "Clear All",
              onPressed: _clearAll,
            )
        ],
      ),
      body: Column(
        children: [
          // 1. SUMMARY HEADER
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Merge Utility", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
                      SizedBox(height: 5),
                      Text("Consolidate Logs", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
                      SizedBox(height: 5),
                      Text("Combine multiple CSVs into one master file with earliest entry times.", style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
                  child: Column(
                    children: [
                      Text("${_selectedFiles.length}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.indigo)),
                      Text("Files", style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                )
              ],
            ),
          ),

          // 2. SUCCESS CARD
          if (_mergedCount > 0)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border.all(color: Colors.green.shade200),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Merge Successful!", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                          Text("Created $_mergedCount unique records.", style: TextStyle(color: Colors.green.shade700)),
                          Text("Saved to: Documents", style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 3. FILE LIST AREA
          Expanded(
            child: _selectedFiles.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open_rounded, size: 80, color: Colors.grey.shade300),
                  SizedBox(height: 15),
                  Text("No files selected", style: TextStyle(color: Colors.grey, fontSize: 16)),
                  SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _addFiles,
                    icon: Icon(Icons.add),
                    label: Text("Add CSV Files"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                    ),
                  )
                ],
              ),
            )
                : ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: _selectedFiles.length,
              itemBuilder: (context, index) {
                return Card(
                  elevation: 2,
                  margin: EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.indigo.shade50,
                      child: Icon(Icons.description, color: Colors.indigo, size: 20),
                    ),
                    title: Text(
                      _selectedFiles[index].path.split('\\').last, // Show Filename
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text(
                      _selectedFiles[index].parent.path, // Show Folder
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.close, color: Colors.grey),
                      onPressed: () => _removeFile(index),
                    ),
                  ),
                );
              },
            ),
          ),

          // 4. BOTTOM ACTION BAR
          if (_selectedFiles.isNotEmpty)
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5))],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _addFiles,
                      icon: Icon(Icons.add),
                      label: Text("Add More"),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        side: BorderSide(color: Colors.indigo),
                      ),
                    ),
                  ),
                  SizedBox(width: 15),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _processFiles,
                      icon: _isProcessing
                          ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Icon(Icons.merge_type),
                      label: Text(_isProcessing ? "Merging..." : "MERGE NOW"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 18),
                        elevation: 5,
                      ),
                    ),
                  ),
                ],
              ),
            )
        ],
      ),
    );
  }
}

class AttendanceRecord {
  final String id;
  final String name;
  final String hall;
  final String originalTimeStr;
  final DateTime rawTime;

  AttendanceRecord(this.id, this.name, this.hall, this.originalTimeStr, this.rawTime);
}