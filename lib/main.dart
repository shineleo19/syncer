import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart'; // <--- Import this
import 'attendance_model.dart';
import 'data_provider.dart';
import 'analysis_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- FIX FOR WINDOWS ONEDRIVE LOCKING ISSUE ---
  // Instead of Documents (synced), we use SupportDirectory (local AppData)
  final appDir = await getApplicationSupportDirectory();
  Hive.init(appDir.path);
  // ----------------------------------------------

  Hive.registerAdapter(AttendanceLogAdapter());

  runApp(SyncerApp());
}

class SyncerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DataProvider()..initDB(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Syncer Analysis',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        ),
        home: AnalysisDashboard(),
      ),
    );
  }
}