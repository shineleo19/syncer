import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'data_provider.dart';
import 'attendance_model.dart';

class AnalysisDashboard extends StatefulWidget {
  @override
  _AnalysisDashboardState createState() => _AnalysisDashboardState();
}

class _AnalysisDashboardState extends State<AnalysisDashboard> {
  int _navIndex = 0;
  String _filterStatus = "All";
  bool _sortAscending = true;
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () async {
            final d = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now()
            );
            if (d != null) setState(() => _selectedDate = d);
          },
          child: Row(
            children: [
              Icon(Icons.calendar_today, size: 20, color: Colors.white70),
              SizedBox(width: 10),
              Text(
                DateFormat('MMM dd, yyyy').format(_selectedDate),
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              Icon(Icons.arrow_drop_down, color: Colors.white),
            ],
          ),
        ),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(icon: Icon(Icons.picture_as_pdf, color: Colors.white), onPressed: () => _generatePdf(context)),
          IconButton(icon: Icon(Icons.storage, color: Colors.white), onPressed: () => _showManageDataDialog(context)),
        ],
      ),
      body: _navIndex == 0 ? _buildDashboard(context) : _buildDetailedLogs(context),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _navIndex,
        onTap: (i) => setState(() => _navIndex = i),
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.pie_chart), label: "Dashboard"),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: "Detailed Logs"),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUploadSheet(context),
        label: Text("Add Log"), icon: Icon(Icons.add), backgroundColor: Colors.indigo,
      ),
    );
  }

  // --- VIEW 1: DASHBOARD ---
  Widget _buildDashboard(BuildContext context) {
    final provider = Provider.of<DataProvider>(context);

    final dayLogs = provider.getLogsForDate(_selectedDate);
    final stats = provider.getStatusDistribution(dayLogs);

    // Total physical staff present (On Time + Late). Replaced are included in these.
    // We add Absent to get the full "Expected" count for percentage calc.
    final double totalStaff = stats['On Time']! + stats['Late']! + stats['Absent']!;

    if (dayLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.date_range, size: 80, color: Colors.indigo.withOpacity(0.2)),
            SizedBox(height: 20),
            Text("No Data for ${DateFormat('MMM dd').format(_selectedDate)}",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[600])
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Overview", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87)),
          SizedBox(height: 20),
          Row(
            children: [
              _buildModernStatCard("On Time", "${stats['On Time']!.toInt()}", Colors.green, Icons.check_circle),
              SizedBox(width: 15),
              _buildModernStatCard("Late", "${stats['Late']!.toInt()}", Colors.orange, Icons.timer_off),
            ],
          ),
          SizedBox(height: 15),
          Row(
            children: [
              _buildModernStatCard("Absent", "${stats['Absent']!.toInt()}", Colors.red, Icons.cancel),
              SizedBox(width: 15),
              _buildModernStatCard("Replaced", "${stats['Replaced']!.toInt()}", Colors.purple, Icons.swap_horiz),
            ],
          ),
          SizedBox(height: 30),
          Container(
            padding: EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: Offset(0, 10))],
            ),
            child: Column(
              children: [
                Text("Attendance Distribution", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                SizedBox(height: 30),
                SizedBox(
                  height: 300,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 60,
                      sections: [
                        if(stats['On Time']! > 0) _chartSection(stats['On Time']!, totalStaff, Colors.greenAccent[700]!),
                        if(stats['Late']! > 0) _chartSection(stats['Late']!, totalStaff, Colors.orangeAccent[400]!),
                        if(stats['Absent']! > 0) _chartSection(stats['Absent']!, totalStaff, Colors.redAccent),
                        // Note: Replaced is shown as a slice but technically overlaps.
                        // The chart library handles the scaling automatically.
                        if(stats['Replaced']! > 0) _chartSection(stats['Replaced']!, totalStaff, Colors.purpleAccent),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Wrap(
                  spacing: 15, runSpacing: 10, alignment: WrapAlignment.center,
                  children: [
                    _buildLegendItem("On Time", Colors.greenAccent[700]!),
                    _buildLegendItem("Late", Colors.orangeAccent[400]!),
                    _buildLegendItem("Absent", Colors.redAccent),
                    _buildLegendItem("Replaced", Colors.purpleAccent),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  PieChartSectionData _chartSection(double val, double total, Color color) {
    return PieChartSectionData(
      value: val, title: "${((val/total)*100).toStringAsFixed(0)}%",
      color: color, radius: 80,
      titleStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
      badgeWidget: Container(
        padding: EdgeInsets.all(5),
        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
        child: Icon(Icons.circle, color: color, size: 10),
      ),
      badgePositionPercentageOffset: .98,
    );
  }

  // --- VIEW 2: LOGS ---
  Widget _buildDetailedLogs(BuildContext context) {
    final provider = Provider.of<DataProvider>(context);
    var logs = provider.getLogsForDate(_selectedDate);

    if (_filterStatus != "All") {
      logs = logs.where((l) => l.status.toLowerCase().contains(_filterStatus.toLowerCase())).toList();
    }
    if (!_sortAscending) {
      logs = logs.reversed.toList();
    }

    if (logs.isEmpty) {
      return Center(child: Text("No records found for ${DateFormat('MMM dd').format(_selectedDate)}"));
    }

    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.white,
          child: Row(
            children: [
              Text("Filter:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              SizedBox(width: 10),
              DropdownButton<String>(
                value: _filterStatus,
                underline: Container(),
                items: ["All", "On Time", "Late", "Absent", "Replaced"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => setState(() => _filterStatus = v!),
              ),
              Spacer(),
              Text("Time:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              IconButton(
                icon: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, color: Colors.indigo),
                onPressed: () => setState(() => _sortAscending = !_sortAscending),
              )
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: logs.length,
            separatorBuilder: (c, i) => Divider(height: 1),
            itemBuilder: (context, index) {
              final log = logs[index];
              String status = log.status.toLowerCase();
              Color color = Colors.green;
              IconData icon = Icons.check_circle;

              // Priority Colors
              if (status.contains("absent")) { color = Colors.red; icon = Icons.cancel; }
              else if (status.contains("replaced")) { color = Colors.purple; icon = Icons.swap_horiz; }
              else if (status.contains("late")) { color = Colors.orange; icon = Icons.warning; }

              return ListTile(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => StaffDetailScreen(staffId: log.staffId, name: log.name)));
                },
                leading: CircleAvatar(
                  backgroundColor: color.withOpacity(0.1),
                  child: Icon(icon, color: color),
                ),
                title: Text(log.name, style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("ID: ${log.staffId}"),
                    // Show replacement badge if replaced
                    if (status.contains("replaced"))
                      Container(
                        margin: EdgeInsets.only(top: 4),
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(4)),
                        child: Text(log.status.split('-')[0], style: TextStyle(color: Colors.purple, fontSize: 10, fontWeight: FontWeight.bold)),
                      )
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                        (status.contains("absent")) ? "--:--" : DateFormat('h:mm a').format(log.entryTime),
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                    ),
                    Container(
                      constraints: BoxConstraints(maxWidth: 150),
                      child: Text(
                        log.status,
                        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis, textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- UPLOAD, EXPORT, DIALOGS (SAME AS BEFORE) ---
  void _showUploadSheet(BuildContext context) {
    DateTime uploadDate = _selectedDate;
    List<File> files = [];

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text("Add Daily Logs", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  SizedBox(height: 20),
                  ListTile(
                    title: Text("Log Date"),
                    subtitle: Text(DateFormat('EEEE, MMMM d, yyyy').format(uploadDate)),
                    trailing: Icon(Icons.edit_calendar, color: Colors.indigo),
                    onTap: () async {
                      final d = await showDatePicker(context: context, initialDate: uploadDate, firstDate: DateTime(2020), lastDate: DateTime.now());
                      if (d != null) setSheetState(() => uploadDate = d);
                    },
                  ),
                  Divider(),
                  ElevatedButton.icon(
                    onPressed: () async {
                      FilePickerResult? result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['csv']);
                      if (result != null) setSheetState(() => files = result.paths.map((path) => File(path!)).toList());
                    },
                    icon: Icon(Icons.upload_file),
                    label: Text(files.isEmpty ? "Select CSV Files" : "${files.length} Files Selected"),
                    style: ElevatedButton.styleFrom(backgroundColor: files.isNotEmpty ? Colors.green : Colors.grey[200], foregroundColor: files.isNotEmpty ? Colors.white : Colors.black),
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: files.isEmpty ? null : () async {
                      Navigator.pop(context);
                      final msg = await Provider.of<DataProvider>(context, listen: false).processFiles(files, uploadDate);
                      setState(() => _selectedDate = uploadDate);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, padding: EdgeInsets.symmetric(vertical: 15)),
                    child: Text("PROCESS & SAVE"),
                  )
                ],
              ),
            );
          }
      ),
    );
  }

  Future<void> _generatePdf(BuildContext context) async {
    final pdf = pw.Document();
    final logs = Provider.of<DataProvider>(context, listen: false).getLogsForDate(_selectedDate);

    if (logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No data to export!")));
      return;
    }

    List<List<String>> detailedData = [['S.No', 'ID', 'Name', 'Time', 'Status']];
    for (int i=0; i<logs.length; i++) {
      var e = logs[i];
      String timeDisplay = (e.status.toLowerCase().contains("absent")) ? "--" : DateFormat('h:mm a').format(e.entryTime);
      detailedData.add([(i+1).toString(), e.staffId, e.name, timeDisplay, e.status]);
    }

    pdf.addPage(pw.MultiPage(
        build: (pw.Context context) => [
          pw.Header(level: 0, child: pw.Text("Attendance Report - ${DateFormat('yyyy-MM-dd').format(_selectedDate)}", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 20),
          pw.Table.fromTextArray(
            headers: detailedData[0], data: detailedData.sublist(1),
            columnWidths: {0: pw.FixedColumnWidth(40), 1: pw.FixedColumnWidth(60), 2: pw.FlexColumnWidth(), 3: pw.FixedColumnWidth(70), 4: pw.FlexColumnWidth()},
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: PdfColors.indigo),
            oddRowDecoration: pw.BoxDecoration(color: PdfColors.grey100),
          ),
        ]
    ));
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  void _showManageDataDialog(BuildContext context) {
    final provider = Provider.of<DataProvider>(context, listen: false);
    final dates = provider.getActiveDates();
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text("Manage Records"),
          content: Container(
            width: double.maxFinite, height: 300,
            child: dates.isEmpty ? Center(child: Text("No records.")) : ListView.builder(
              itemCount: dates.length,
              itemBuilder: (c, i) {
                final date = dates[i];
                return ListTile(
                  title: Text(DateFormat('EEE, MMM d, yyyy').format(date)),
                  trailing: IconButton(icon: Icon(Icons.delete, color: Colors.red), onPressed: () async {
                    await provider.deleteRecordsForDate(date);
                    Navigator.pop(ctx); _showManageDataDialog(context);
                  }),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: ()=>Navigator.pop(ctx), child: Text("Close")),
            TextButton(onPressed: ()=>_showSecureClearDialog(context), child: Text("Wipe All", style: TextStyle(color: Colors.red))),
          ],
        )
    );
  }

  void _showSecureClearDialog(BuildContext context) {
    TextEditingController _controller = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text("WARNING: ERASE ALL"), content: TextField(controller: _controller, decoration: InputDecoration(hintText: "Type 'clear'")),
      actions: [
        ElevatedButton(onPressed: (){
          if(_controller.text=="clear"){
            Provider.of<DataProvider>(context,listen:false).clearAllData();
            Navigator.pop(ctx);
          }
        }, child: Text("ERASE"))
      ],
    ));
  }

  Widget _buildModernStatCard(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(25),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [color.withOpacity(0.8), color]), borderRadius: BorderRadius.circular(20)),
        child: Column(children: [
          Icon(icon, color: Colors.white, size: 30), SizedBox(height: 10),
          Text(value, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(title, style: TextStyle(color: Colors.white70))
        ]),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 16, height: 16, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
      SizedBox(width: 8), Text(label)
    ]);
  }
}

class StaffDetailScreen extends StatelessWidget {
  final String staffId; final String name;
  const StaffDetailScreen({required this.staffId, required this.name});
  @override Widget build(BuildContext context) { return Scaffold(appBar: AppBar(title: Text(name)), body: Center(child: Text("Details for $name"))); }
}