import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../theme_provider.dart';
import '../utils/conversion_utilities.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../localization/app_localizations.dart';
import '../localization/language_provider.dart';

// Extension to calculate the week of year for a date
extension DateTimeExtension on DateTime {
  int get weekOfYear {
    // The first week of the year is the week that contains January 4th
    final dayOfYear = int.parse(DateFormat('D').format(this));
    // Calculate the day of the week (Mon=1...Sun=7)
    final weekDay = weekday;
    // Calculate the number of days from the beginning of the year
    final daysFromStartToFirstWeekday = weekDay - (weekday < 8 ? 1 : 0);
    // Calculate the week number
    return ((dayOfYear - daysFromStartToFirstWeekday) / 7).ceil();
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  HistoryScreenState createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  String _selectedPeriod = 'daily';
  DateTime? _startDate;
  DateTime? _endDate;
  String _energyUnit = 'kWh';

  // Map to store export data
  Map<String, double> _exportData = {};

  // Add current language tracker
  String _currentLanguage = '';

  @override
  void initState() {
    super.initState();
    _loadInitialDates();
    _loadSettings();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageProvider = Provider.of<LanguageProvider>(context);
    if (_currentLanguage != languageProvider.locale.languageCode) {
      _currentLanguage = languageProvider.locale.languageCode;
      // Force rebuild when language changes
      setState(() {});
    }
  }
  
  // Load user preferences for energy unit
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _energyUnit = prefs.getString('energyUnit') ?? 'kWh';
      });
    } catch (e) {
      // Handle error silently
    }
  }

  void _loadInitialDates() {
    _startDate = DateTime.now().subtract(const Duration(days: 30));
    _endDate = DateTime.now();
  }

  // Format energy values with current unit
  String _formatEnergyValue(double valueInKWh) {
    try {
      double convertedValue = ConversionUtilities.convertEnergy(
        valueInKWh, 
        'kWh', 
        _energyUnit
      );
      return "${convertedValue.toStringAsFixed(2)} $_energyUnit";
    } catch (e) {
      return "$valueInKWh kWh";
    }
  }

  Stream<QuerySnapshot> _getHistoryStream() {
    String userId = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('consumption_history')
        .orderBy('date', descending: true)
        .where('date', isGreaterThanOrEqualTo: _startDate?.toIso8601String().split('T')[0] ?? '')
        .where('date', isLessThanOrEqualTo: _endDate?.toIso8601String().split('T')[0] ?? '')
        .limit(30)
        .snapshots();
  }

  // Get list of devices that contributed to consumption on a specific date
  List<Widget> _getDeviceConsumptionList(Map<String, dynamic> deviceData, bool isDarkTheme) {
    List<Widget> widgets = [];
    
    if (deviceData.containsKey('devices_consumption')) {
      Map<String, dynamic> devicesConsumption = Map<String, dynamic>.from(deviceData['devices_consumption']);
      
      devicesConsumption.forEach((deviceId, data) {
        String deviceName = "${data['manufacturer'] ?? 'Unknown'} ${data['model'] ?? 'Device'}";
        double consumption = (data['daily_consumption'] ?? 0.0).toDouble();
        double convertedConsumption = ConversionUtilities.convertEnergy(consumption, 'kWh', _energyUnit);
        
        // Add device consumption info widget
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  deviceName,
                  style: GoogleFonts.poppins(
                    color: isDarkTheme ? Colors.white70 : Colors.black87,
                    fontSize: 13,
                  ),
                ),
                Text(
                  "${convertedConsumption.toStringAsFixed(2)} $_energyUnit",
                  style: GoogleFonts.poppins(
                    color: isDarkTheme ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          )
        );
      });
    }
    
    if (widgets.isEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(
            "no_data".tr(context),
            style: GoogleFonts.poppins(
              color: isDarkTheme ? Colors.white70 : Colors.black87,
              fontStyle: FontStyle.italic,
              fontSize: 13,
            ),
          ),
        )
      );
    }
    
    return widgets;
  }

  Future<void> _selectDateRange() async {
    DateTimeRange? pickedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: _startDate ?? DateTime.now().subtract(const Duration(days: 30)),
        end: _endDate ?? DateTime.now(),
      ),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(primary: Colors.blueAccent),
          ),
          child: child!,
        );
      },
    );
    if (pickedRange != null) {
      setState(() {
        _startDate = pickedRange.start;
        _endDate = pickedRange.end;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Date range updated: ${DateFormat('dd/MM/yyyy').format(_startDate!)} - ${DateFormat('dd/MM/yyyy').format(_endDate!)}",
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.blueAccent,
          ),
        );
      });
    }
  }

  Future<void> _exportHistory() async {
    try {
      // Prepare export data
      _exportData = {};
      String userId = FirebaseAuth.instance.currentUser!.uid;
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .where('date', isGreaterThanOrEqualTo: _startDate?.toIso8601String().split('T')[0] ?? '')
          .where('date', isLessThanOrEqualTo: _endDate?.toIso8601String().split('T')[0] ?? '')
          .get();

      for (var doc in snapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        double rawConsumption = data['total_consumption']?.toDouble() ?? 0.0;
        // Convert to selected unit for export
        double convertedConsumption = ConversionUtilities.convertEnergy(
          rawConsumption, 
          'kWh', 
          _energyUnit
        );
        _exportData[data['date'] ?? ''] = convertedConsumption;
      }

      final directory = await getApplicationDocumentsDirectory();
      final csv = "Date,Consumption ($_energyUnit)\n${_exportData.entries.map((e) => "${e.key},${e.value}").join("\n")}";
      final file = File('${directory.path}/consumption_history.csv');
      await file.writeAsString(csv);
      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path)], text: 'Consumption History Export');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error exporting data: $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool isDarkTheme = themeProvider.isDarkTheme;
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDarkTheme 
                ? [Color.fromRGBO(68, 138, 255, 0.2), Colors.black]
                : [Colors.white, Colors.grey[300]!],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 80.0),
            child: StreamBuilder<QuerySnapshot>(
              stream: _getHistoryStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.blueAccent));
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      "error".tr(context) + ": ${snapshot.error}",
                      style: GoogleFonts.poppins(
                        color: isDarkTheme ? Colors.white70 : Colors.black87, 
                        fontSize: 18
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                List<FlSpot> chartData = [];
                List<String> dates = [];
                double totalPeriodConsumption = 0.0;
                int index = 0;

                final docs = snapshot.data?.docs ?? [];
                if (_selectedPeriod == 'daily') {
                  for (var doc in docs) {
                    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
                    double consumption = data['total_consumption']?.toDouble() ?? 0.0;
                    String dateStr = data['date'] ?? doc.id;
                    chartData.add(FlSpot(index.toDouble(), consumption));
                    dates.add(dateStr);
                    totalPeriodConsumption += consumption;
                    index++;
                  }
                  chartData = chartData.reversed.toList();
                  dates = dates.reversed.toList();
                } else if (_selectedPeriod == 'weekly') {
                  Map<String, double> weeklyData = {};
                  for (var doc in docs) {
                    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
                    DateTime date = DateTime.parse(data['date'] ?? doc.id);
                    String weekKey = "${date.year}-W${date.weekOfYear}";
                    weeklyData[weekKey] = (weeklyData[weekKey] ?? 0.0) + (data['total_consumption']?.toDouble() ?? 0.0);
                  }
                  var sortedWeeks = weeklyData.keys.toList()
                    ..sort((a, b) {
                      final aParts = a.split('-W');
                      final bParts = b.split('-W');
                      final aYear = int.parse(aParts[0]);
                      final bYear = int.parse(bParts[0]);
                      final aWeek = int.parse(aParts[1]);
                      final bWeek = int.parse(bParts[1]);
                      return aYear.compareTo(bYear) != 0 ? aYear.compareTo(bYear) : aWeek.compareTo(bWeek);
                    });
                  for (var week in sortedWeeks) {
                    double consumption = weeklyData[week]!;
                    chartData.add(FlSpot(index.toDouble(), consumption));
                    dates.add(week);
                    totalPeriodConsumption += consumption;
                    index++;
                  }
                } else if (_selectedPeriod == 'monthly') {
                  Map<String, double> monthlyData = {};
                  for (var doc in docs) {
                    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
                    DateTime date = DateTime.parse(data['date'] ?? doc.id);
                    String monthKey = DateFormat('yyyy-MM').format(date);
                    monthlyData[monthKey] = (monthlyData[monthKey] ?? 0.0) + (data['total_consumption']?.toDouble() ?? 0.0);
                  }
                  var sortedMonths = monthlyData.keys.toList()..sort();
                  for (var month in sortedMonths) {
                    double consumption = monthlyData[month]!;
                    chartData.add(FlSpot(index.toDouble(), consumption));
                    dates.add(month);
                    totalPeriodConsumption += consumption;
                    index++;
                  }
                }

                return ListView(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "energy_consumption".tr(context),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.calendar_month,
                            color: isDarkTheme ? Colors.white : Colors.black87,
                          ),
                          onPressed: _selectDateRange,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      "showing_data_from".trParams(context, [
                        DateFormat('MMM d, yyyy').format(_startDate ?? DateTime.now().subtract(const Duration(days: 30))),
                        DateFormat('MMM d, yyyy').format(_endDate ?? DateTime.now())
                      ]),
                      style: GoogleFonts.poppins(
                        color: isDarkTheme ? Colors.white70 : Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 25),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDarkTheme ? Colors.white.withAlpha(26) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildPeriodButton("Daily", _selectedPeriod == 'daily', isDarkTheme),
                          _buildPeriodButton("Weekly", _selectedPeriod == 'weekly', isDarkTheme),
                          _buildPeriodButton("Monthly", _selectedPeriod == 'monthly', isDarkTheme),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      height: 250,
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: isDarkTheme ? Colors.white.withAlpha(26) : Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(13),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: _buildHistoryChart(chartData, dates, isDarkTheme),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "total_consumption".tr(context),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _formatEnergyValue(totalPeriodConsumption),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.blue[300] : Colors.blue[700],
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: _exportHistory,
                      icon: const Icon(Icons.download),
                      label: Text("export_data".tr(context), style: GoogleFonts.poppins()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 25),
                    Text(
                      "daily_breakdown".tr(context),
                      style: GoogleFonts.poppins(
                        color: isDarkTheme ? Colors.white : Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      itemCount: _selectedPeriod == 'daily' ? docs.length : 0,
                      itemBuilder: (context, index) {
                        var doc = docs[index];
                        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
                        String dateStr = data['date'] ?? doc.id;
                        double consumption = data['total_consumption']?.toDouble() ?? 0.0;
                        double convertedConsumption = ConversionUtilities.convertEnergy(
                          consumption, 
                          'kWh', 
                          _energyUnit
                        );
                        
                        DateTime date = DateTime.parse(dateStr);
                        String formattedDate = DateFormat('MMM d, yyyy').format(date);
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 2,
                          color: isDarkTheme ? Color(0xFF1A1F38) : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ExpansionTile(
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  formattedDate,
                                  style: GoogleFonts.poppins(
                                    color: isDarkTheme ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  "${convertedConsumption.toStringAsFixed(2)} $_energyUnit",
                                  style: GoogleFonts.poppins(
                                    color: isDarkTheme ? Colors.blue[300] : Colors.blue[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "devices_label".tr(context),
                                      style: GoogleFonts.poppins(
                                        color: isDarkTheme ? Colors.white : Colors.black,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Divider(color: isDarkTheme ? Colors.white30 : Colors.black12),
                                    ..._getDeviceConsumptionList(data, isDarkTheme),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodButton(String label, bool isSelected, bool isDarkTheme) {
    return TextButton(
      onPressed: () {
        setState(() {
          _selectedPeriod = label.toLowerCase();
        });
      },
      child: Text(
        label,
        style: GoogleFonts.poppins(
          color: isSelected ? Colors.blueAccent : isDarkTheme ? Colors.white70 : Colors.black87,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildHistoryChart(List<FlSpot> chartData, List<String> dates, bool isDarkTheme) {
    if (chartData.isEmpty || chartData.every((spot) => spot.y == 0)) {
      chartData = [FlSpot(0, 0)];
      dates = [_startDate?.toIso8601String().split('T')[0] ?? DateTime.now().toIso8601String().split('T')[0]];
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 2,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: isDarkTheme ? Colors.grey[800]! : Colors.grey[300]!,
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                final int index = value.toInt();
                if (index >= 0 && index < dates.length) {
                  String label = '';
                  if (_selectedPeriod == 'daily') {
                    DateTime date = DateTime.parse(dates[index]);
                    label = DateFormat('dd/MM').format(date);
                  } else if (_selectedPeriod == 'weekly') {
                    label = dates[index].split('-W')[1];
                  } else if (_selectedPeriod == 'monthly') {
                    label = DateFormat('MMM').format(DateTime.parse('${dates[index]}-01'));
                  }
                  return Text(
                    label,
                    style: GoogleFonts.poppins(
                      color: isDarkTheme ? Colors.grey[400] : Colors.grey[700],
                      fontSize: 12,
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                double convertedValue = ConversionUtilities.convertEnergy(
                  value,
                  'kWh',
                  _energyUnit
                );
                return Text(
                  convertedValue.toStringAsFixed(1),
                  style: GoogleFonts.poppins(
                    color: isDarkTheme ? Colors.grey[400] : Colors.grey[700],
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (chartData.length - 1).toDouble(),
        minY: 0,
        maxY: chartData.map((spot) => spot.y).reduce((a, b) => a > b ? a : b) * 1.5,
        lineBarsData: [
          LineChartBarData(
            spots: chartData,
            isCurved: true,
            color: isDarkTheme ? Colors.blue[400] : Colors.blue[600],
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: isDarkTheme
                  ? Colors.blue[400]!.withAlpha(51)
                  : Colors.blue[200]!.withAlpha(77),
            ),
          ),
        ],
      ),
    );
  }
}