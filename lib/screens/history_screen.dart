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
import '../database/database_helper.dart';
import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;

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
  String _selectedDate = DateTime.now().toIso8601String().split('T')[0];
  Map<int, double> _hourlyData = {};
  
  // Add these missing variable declarations
  List<FlSpot> _chartData = [];
  List<String> _dateLabels = [];
  
  DateTime? _startDate;
  DateTime? _endDate;
  String _energyUnit = 'kWh';

  // Map to store export data
  Map<String, double> _exportData = {};

  // Add current language tracker
  String _currentLanguage = '';

  // Add new variables for hourly data
  List<FlSpot> _hourlyChartData = [];
  Map<String, dynamic> _deviceBreakdownData = {};
  bool _isLoading = false;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadInitialDates();
    _loadSettings();
    // Force initial data load for current user
    _loadUserConsumptionData();
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
  
  // New method to trigger immediate data refresh
  Future<void> _loadUserConsumptionData() async {
    if (!mounted) return;
    
    setState(() {
      _isRefreshing = true;
    });
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Force an immediate data update
        await DatabaseHelper.instance.recordDeviceUsage(user.uid);
        
        // If hourly view is selected, refresh hourly data
        if (_selectedPeriod == 'hourly') {
          await _loadHourlyData(_selectedDate);
        } else {
          // For other periods, force date range data refresh
          await _loadDateRangeData();
        }
      }
    } catch (e) {
      developer.log("Error refreshing consumption data: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
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

  bool get isMounted => mounted;

  // Helper method to format energy values
  String _formatEnergyValue(double value) {
    try {
      double convertedValue = ConversionUtilities.convertEnergy(
        value,
        'kWh', 
        _energyUnit
      );
      return "${convertedValue.toStringAsFixed(1)} $_energyUnit";
    } catch (e) {
      return "${value.toStringAsFixed(1)} kWh";
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
              "date_range_updated".trParams(context, [DateFormat('dd/MM/yyyy').format(_startDate!), DateFormat('dd/MM/yyyy').format(_endDate!)]),
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.blueAccent,
          ),
        );
      });
      
      // Load data for the new date range
      _loadDateRangeData();
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
            child: RefreshIndicator(
              onRefresh: _loadUserConsumptionData,
              color: Colors.blue,
            child: StreamBuilder<QuerySnapshot>(
              stream: _getHistoryStream(),
              builder: (context, snapshot) {
                  if (_selectedPeriod == 'hourly') {
                    if (_isLoading) {
                  return const Center(child: CircularProgressIndicator(color: Colors.blueAccent));
                }
                    
                    List<FlSpot> chartData = _hourlyChartData;
                    List<String> dates = List<String>.generate(24, (i) => i.toString().padLeft(2, '0') + ':00');
                    double totalPeriodConsumption = _hourlyData.values.fold(0.0, (sum, value) => sum + value);
                    
                    return _buildHistoryContent(
                      chartData, 
                      dates, 
                      totalPeriodConsumption, 
                      isDarkTheme,
                      isHourlyView: true
                    );
                  }
                  
                  // Handle other time periods (daily, weekly, monthly)
                  if (snapshot.connectionState == ConnectionState.waiting || _isRefreshing) {
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

                  final docs = snapshot.data?.docs ?? [];
                  
                  // If the selected period is weekly or monthly, format the X-axis as requested
                  if (_selectedPeriod == 'weekly' || _selectedPeriod == 'monthly') {
                    _createCustomFormattedData(docs, isDarkTheme);
                    
                    double totalPeriodConsumption = _chartData.fold(0.0, (sum, spot) => sum + spot.y);
                    return _buildHistoryContent(_chartData, _dateLabels, totalPeriodConsumption, isDarkTheme, isHourlyView: false, docs: docs);
                  }
                  
                  // For daily, use the standard approach
                List<FlSpot> chartData = [];
                List<String> dates = [];
                double totalPeriodConsumption = 0.0;

                  // Get all data in date range for consistent display
                  Map<String, double> dayConsumption = {};
                  
                  for (var doc in docs) {
                    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
                    double consumption = data['total_consumption']?.toDouble() ?? 0.0;
                    String dateStr = data['date'] ?? doc.id;
                    dayConsumption[dateStr] = consumption;
                    totalPeriodConsumption += consumption;
                  }
                  
                  List<DateTime> allDates = [];
                  DateTime currentDate = _startDate ?? DateTime.now().subtract(const Duration(days: 30));
                  DateTime endDate = _endDate ?? DateTime.now();
                  
                  while (!currentDate.isAfter(endDate)) {
                    allDates.add(currentDate);
                    currentDate = currentDate.add(const Duration(days: 1));
                  }
                  
                  // Sort dates oldest to newest
                  allDates.sort((a, b) => a.compareTo(b));
                  
                  // Create a point for each day
                  for (int i = 0; i < allDates.length; i++) {
                    String dateStr = allDates[i].toIso8601String().split('T')[0];
                    double consumption = dayConsumption[dateStr] ?? 0.0;
                    chartData.add(FlSpot(i.toDouble(), consumption));
                    dates.add(dateStr);
                  }
                  
                  // Store data for future use
                  _chartData = chartData;
                  _dateLabels = dates;
                  
                  return _buildHistoryContent(chartData, dates, totalPeriodConsumption, isDarkTheme, isHourlyView: false, docs: docs);
                },
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadUserConsumptionData,
        backgroundColor: Colors.blue,
        child: const Icon(Icons.refresh, color: Colors.white),
      ),
    );
  }

  Widget _buildPeriodButton(String label, bool isSelected, bool isDarkTheme) {
    return TextButton(
      onPressed: () {
        setState(() {
          _selectedPeriod = label.toLowerCase();
          // If hourly is selected, load today's hourly data
          if (_selectedPeriod == 'hourly') {
            _loadHourlyData(DateTime.now().toIso8601String().split('T')[0]);
          }
        });
      },
      child: Text(
        label,
        style: GoogleFonts.poppins(
          color: isSelected ? Colors.blueAccent : isDarkTheme ? Colors.white70 : Colors.black87,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildHistoryChart(List<FlSpot> chartData, List<String> dates, bool isDarkTheme) {
    // Check if we have data to display
    if (chartData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart_outlined,
              size: 50,
              color: isDarkTheme ? Colors.white54 : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              "no_consumption_data".tr(context),
              style: GoogleFonts.poppins(
                color: isDarkTheme ? Colors.white70 : Colors.black54,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    // Find maximum Y value with 20% padding for better visualization
    double maxY = chartData.map((spot) => spot.y).reduce((a, b) => a > b ? a : b);
    maxY = maxY * 1.2;
    
    // If maxY is too small, set a minimum value
    if (maxY < 0.5) maxY = 1.0;
    
    // Determine appropriate step size for vertical grid lines
    double verticalInterval = _getVerticalInterval();
    
    // Modern chart appearance
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: isDarkTheme ? Colors.black26 : Colors.black12,
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: maxY / 5, // Five horizontal grid lines
            verticalInterval: verticalInterval,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: isDarkTheme ? Colors.grey[800]!.withOpacity(0.6) : Colors.grey[300]!,
                strokeWidth: 0.8,
                dashArray: [5, 5], // Dashed lines for horizontal grid
              );
            },
            getDrawingVerticalLine: (value) {
              return FlLine(
                color: isDarkTheme ? Colors.grey[900]!.withOpacity(0.3) : Colors.grey[200]!,
                strokeWidth: 0.5,
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
                reservedSize: 35,  // More space for labels
                interval: _getXAxisLabelInterval(),
                getTitlesWidget: (value, meta) {
                  final int index = value.toInt();
                  if (index < 0 || index >= dates.length) {
                    return Container(); // Return empty for out of range indices
                  }
                  
                  String label = _formatXAxisLabel(dates[index], index);
                  
                  return Padding(
                    padding: const EdgeInsets.only(top: 10.0),
                    child: SizedBox(
                      width: 60,  // Fixed width for consistency
                      child: Text(
                        label,
                        style: GoogleFonts.poppins(
                          color: isDarkTheme ? Colors.white70 : Colors.black54,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return Text(
                    _formatEnergyValue(value),
                    style: GoogleFonts.poppins(
                      color: isDarkTheme ? Colors.white70 : Colors.black54,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              bottom: BorderSide(
                color: isDarkTheme ? Colors.white24 : Colors.black12,
                width: 1,
              ),
              left: BorderSide(
                color: isDarkTheme ? Colors.white24 : Colors.black12,
                width: 1,
              ),
              right: BorderSide(color: Colors.transparent),
              top: BorderSide(color: Colors.transparent),
            ),
          ),
          minX: 0,
          maxX: chartData.length - 1.0,
          minY: 0,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: chartData,
              isCurved: true,
              curveSmoothness: 0.3, // Smoother curve
              color: Colors.blue.shade500,
              barWidth: 3.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 3.5,
                    color: Colors.white,
                    strokeColor: Colors.blue.shade600,
                    strokeWidth: 2,
                  );
                },
                checkToShowDot: (spot, barData) {
                  // Show dots for hourly view or for significant data points
                  return _selectedPeriod == 'hourly' ? 
                    (spot.y > 0) : 
                    (spot.x.toInt() % 2 == 0 || spot.y > maxY * 0.7);
                },
              ),
              shadow: const Shadow(
                color: Colors.black26,
                offset: Offset(0, 2),
                blurRadius: 2,
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    Colors.blue.shade500.withOpacity(0.5),
                    Colors.blue.shade200.withOpacity(0.1),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                applyCutOffY: true,
                cutOffY: 0,
                spotsLine: BarAreaSpotsLine(
                  show: true,
                  flLineStyle: FlLine(
                    color: Colors.blue.shade300.withOpacity(0.2),
                    strokeWidth: 0.5,
                  ),
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (List<LineBarSpot> touchedSpots) {
                return touchedSpots.map((LineBarSpot touchedSpot) {
                  final int index = touchedSpot.x.toInt();
                  final double value = touchedSpot.y;
                  String tooltipLabel = index < dates.length ? _getTooltipLabel(dates[index]) : "";
                  
                  return LineTooltipItem(
                    '$tooltipLabel\n${_formatEnergyValue(value)}',
                    GoogleFonts.poppins(
                      color: isDarkTheme ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }).toList();
              },
              tooltipPadding: const EdgeInsets.all(10),
              tooltipRoundedRadius: 12,
            ),
            getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
              return spotIndexes.map((spotIndex) {
                return TouchedSpotIndicatorData(
                  FlLine(
                    color: Colors.blue.shade700,
                    strokeWidth: 2,
                    dashArray: [3, 3],
                  ),
                  FlDotData(
                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotCirclePainter(
                        radius: 5,
                        color: Colors.white,
                        strokeColor: Colors.blue.shade600,
                        strokeWidth: 2.5,
                      );
                    },
                  ),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }

  // Get appropriate interval for x-axis labels based on period
  double _getXAxisLabelInterval() {
    switch (_selectedPeriod) {
      case 'hourly':
        return 4; // Show every 4 hours for better spacing
      case 'daily':
        // For daily view, adjust based on number of days
        if (_chartData.length > 28) return 7; // Weekly intervals for month+ views
        if (_chartData.length > 14) return 3; // Every 3 days for 2+ weeks
        if (_chartData.length > 7) return 2;  // Every 2 days for 1+ week
        return 1; // Show every day for short ranges
      case 'weekly':
        return 1; // Show every week
      case 'monthly':
        return 1; // Show every month
      default:
        return 1;
    }
  }
  
  // Get appropriate vertical gridline interval
  double _getVerticalInterval() {
    switch (_selectedPeriod) {
      case 'hourly':
        return 4; // Every 4 hours
      case 'daily':
        return _chartData.length > 14 ? 2 : 1;
      case 'weekly':
        return 1;
      case 'monthly':
        return 1;
      default:
        return 1;
    }
  }
  
  // Format x-axis label based on time period - simplified version
  String _formatXAxisLabel(String dateText, int index) {
    switch (_selectedPeriod) {
      case 'hourly':
        // For hourly, convert '00:00' to '12AM', '13:00' to '1PM', etc.
        try {
          int hour = int.parse(dateText.split(':')[0]);
          if (hour == 0) return '12AM';
          if (hour == 12) return '12PM';
          return hour > 12 ? '${hour - 12}PM' : '${hour}AM';
        } catch (e) {
          return dateText;
        }
      
      case 'daily':
        // For daily, convert ISO date to 'MM/DD' format
        try {
          DateTime date = DateTime.parse(dateText);
          return '${date.month}/${date.day}';
        } catch (e) {
          return dateText;
        }
      
      case 'weekly':
      case 'monthly':
        // For weekly and monthly, just return the label as is (already formatted)
        return dateText;
        
      default:
        return dateText;
    }
  }
  
  // Get detailed tooltip label based on period
  String _getTooltipLabel(String dateText) {
    switch (_selectedPeriod) {
      case 'hourly':
        try {
          int hour = int.parse(dateText.split(':')[0]);
          if (hour == 0) return '12:00 AM';
          if (hour == 12) return '12:00 PM';
          return hour > 12 ? '${hour - 12}:00 PM' : '${hour}:00 AM';
        } catch (e) {
          return dateText;
        }
        
      case 'daily':
        try {
          DateTime date = DateTime.parse(dateText);
          return DateFormat('MMM d, yyyy').format(date);
        } catch (e) {
          return dateText;
        }
        
      case 'weekly':
        // Determine the dates being displayed on hover
        int idx = _dateLabels.indexOf(dateText);
        if (idx >= 0) {
          DateTime now = DateTime.now();
          DateTime startOfWeek = now.subtract(Duration(days: (idx + 1) * 7));
          DateTime endOfWeek = startOfWeek.add(const Duration(days: 6));
          return '${DateFormat('MMM d').format(startOfWeek)} - ${DateFormat('MMM d, yyyy').format(endOfWeek)}';
        }
        return dateText;
        
      case 'monthly':
        try {
          DateTime date = DateTime.parse('${dateText}-01');
          return DateFormat('MMMM yyyy').format(date);
        } catch (e) {
          return dateText;
        }
        
      default:
        return dateText;
    }
  }

  // Build hourly breakdown widget for daily view
  Widget _buildHourlyBreakdown(Map hourlyData, bool isDarkTheme) {
    List<MapEntry<dynamic, dynamic>> sortedEntries = hourlyData.entries.toList()
      ..sort((a, b) => int.parse(a.key.toString()).compareTo(int.parse(b.key.toString())));
    
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: sortedEntries.map((entry) {
        int hour = int.parse(entry.key.toString());
        double value = (entry.value as num).toDouble();
        String timeLabel;
        
        if (hour == 0) {
          timeLabel = '12AM';
        } else if (hour == 12) {
          timeLabel = '12PM';
        } else if (hour > 12) {
          timeLabel = '${hour - 12}PM';
        } else {
          timeLabel = '${hour}AM';
        }
        
        return Container(
          width: 75,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            color: isDarkTheme ? Colors.white.withOpacity(0.1) : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(
                timeLabel,
                style: GoogleFonts.poppins(
                  color: isDarkTheme ? Colors.white70 : Colors.black87,
                  fontSize: 12,
                ),
              ),
              Text(
                "${value.toStringAsFixed(2)} $_energyUnit",
                style: GoogleFonts.poppins(
                  color: isDarkTheme ? Colors.blue[300] : Colors.blue[700],
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // Load data for the selected date range
  Future<void> _loadDateRangeData() async {
    try {
      if (_startDate == null || _endDate == null) return;
      
      String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (userId.isEmpty) return;
      
      // Fetch the data from the database for the selected date range
      List<Map<String, dynamic>> data;
      List<FlSpot> chartSpots = [];
      List<String> dateLabels = [];
      
      switch (_selectedPeriod) {
        case 'daily':
          data = await DatabaseHelper.instance.getDailyConsumption(
            userId, _startDate!, _endDate!
          );
          
          // Create a map of date to consumption for existing data
          Map<String, double> dateConsumptionMap = {};
          for (var entry in data) {
            String dateStr = entry['date'];
            double consumption = entry['total_consumption'] ?? 0.0;
            dateConsumptionMap[dateStr] = consumption;
          }
          
          // Generate all dates in the range
          List<DateTime> allDates = [];
          DateTime currentDate = _startDate!;
          while (currentDate.isBefore(_endDate!.add(const Duration(days: 1)))) {
            allDates.add(currentDate);
            currentDate = currentDate.add(const Duration(days: 1));
          }
          
          // Create a data point for every day in the range
          for (int i = 0; i < allDates.length; i++) {
            String dateStr = allDates[i].toIso8601String().split('T')[0];
            double consumption = dateConsumptionMap[dateStr] ?? 0.0;
            chartSpots.add(FlSpot(i.toDouble(), consumption));
            dateLabels.add(dateStr);
          }
          break;
          
        case 'weekly':
          data = await DatabaseHelper.instance.getWeeklyConsumption(
            userId, _startDate!, _endDate!
          );
          
          // Process weekly data
                  Map<String, double> weeklyData = {};
          
          // First, populate with existing data
          for (var entry in data) {
            DateTime date = DateTime.parse(entry['date']);
                    String weekKey = "${date.year}-W${date.weekOfYear}";
            weeklyData[weekKey] = (weeklyData[weekKey] ?? 0.0) + (entry['total_consumption'] ?? 0.0);
          }
          
          // Generate all weeks in the range
          List<String> allWeeks = [];
          DateTime currentDate = _startDate!;
          while (currentDate.isBefore(_endDate!.add(const Duration(days: 1)))) {
            String weekKey = "${currentDate.year}-W${currentDate.weekOfYear}";
            if (!allWeeks.contains(weekKey)) {
              allWeeks.add(weekKey);
            }
            currentDate = currentDate.add(const Duration(days: 1));
          }
          
          // Sort weeks
          allWeeks.sort();
          
          // Create a data point for every week
          for (int i = 0; i < allWeeks.length; i++) {
            String weekKey = allWeeks[i];
            double consumption = weeklyData[weekKey] ?? 0.0;
            chartSpots.add(FlSpot(i.toDouble(), consumption));
            dateLabels.add(weekKey);
          }
          break;
          
        case 'monthly':
          data = await DatabaseHelper.instance.getMonthlyConsumption(
            userId, _startDate!, _endDate!
          );
          
          // Process monthly data
                  Map<String, double> monthlyData = {};
          
          // First, populate with existing data
          for (var entry in data) {
            DateTime date = DateTime.parse(entry['date']);
                    String monthKey = DateFormat('yyyy-MM').format(date);
            monthlyData[monthKey] = (monthlyData[monthKey] ?? 0.0) + (entry['total_consumption'] ?? 0.0);
          }
          
          // Generate all months in the range
          List<String> allMonths = [];
          DateTime currentDate = DateTime(_startDate!.year, _startDate!.month, 1);
          DateTime endMonth = DateTime(_endDate!.year, _endDate!.month, 1);
          
          while (!currentDate.isAfter(endMonth)) {
            String monthKey = DateFormat('yyyy-MM').format(currentDate);
            allMonths.add(monthKey);
            // Move to next month
            currentDate = DateTime(
              currentDate.month == 12 ? currentDate.year + 1 : currentDate.year,
              currentDate.month == 12 ? 1 : currentDate.month + 1,
              1
            );
          }
          
          // Create a data point for every month
          for (int i = 0; i < allMonths.length; i++) {
            String monthKey = allMonths[i];
            double consumption = monthlyData[monthKey] ?? 0.0;
            chartSpots.add(FlSpot(i.toDouble(), consumption));
            dateLabels.add(monthKey);
          }
          break;
      }
      
      if (mounted) {
        setState(() {
          _chartData = chartSpots;
          _dateLabels = dateLabels;
        });
      }
    } catch (e) {
      developer.log("Error loading date range data: $e");
    }
  }

  // Function to load hourly data for a specific date
  Future<void> _loadHourlyData(String date) async {
    setState(() => _isLoading = true);
    
    try {
      String userId = FirebaseAuth.instance.currentUser!.uid;
      
      // Get enhanced hourly data that includes device breakdown
      Map<String, dynamic> enhancedData = 
          await DatabaseHelper.instance.getHourlyConsumptionEnhanced(userId, date);
      
      setState(() {
        _selectedDate = date;
        
        // Set hourly data for chart
        Map<int, double> hourlyData = Map<int, double>.from(enhancedData['hourly_data'] ?? {});
        _hourlyData = hourlyData;
        
        // Create spots for the chart - ensure we have all 24 hours
        _hourlyChartData = [];
        
        // Create a data point for every hour (0-23), even if consumption is 0
        for (int hour = 0; hour < 24; hour++) {
          double consumption = hourlyData[hour] ?? 0.0;
          _hourlyChartData.add(FlSpot(hour.toDouble(), consumption));
        }
        
        // Store device breakdown data
        _deviceBreakdownData = enhancedData['devices_data'] ?? {};
        
        _isLoading = false;
      });
    } catch (e) {
      developer.log("Error loading hourly data: $e");
      setState(() => _isLoading = false);
    }
  }

  // Build a detailed hourly consumption chart with time-of-day labels
  Widget _buildHourlyConsumptionChart(bool isDarkTheme) {
    if (_hourlyChartData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart,
              size: 50,
              color: isDarkTheme ? Colors.white54 : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              "no_hourly_data".tr(context),
              style: GoogleFonts.poppins(
                color: isDarkTheme ? Colors.white70 : Colors.black54,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }
    
    double maxY = _hourlyChartData.map((spot) => spot.y).reduce((a, b) => a > b ? a : b);
    maxY = maxY * 1.2; // Add 20% padding at the top
    
    // Ensure we have a minimum Y value for the chart
    if (maxY < 0.5) maxY = 1.0;
    
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          "hourly_consumption".tr(context),
          style: GoogleFonts.poppins(
            color: isDarkTheme ? Colors.white : Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 250,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                horizontalInterval: maxY / 4,
                verticalInterval: 4,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: isDarkTheme ? Colors.grey[800]! : Colors.grey[300]!,
                    strokeWidth: 1,
                  );
                },
                getDrawingVerticalLine: (value) {
                  return FlLine(
                    color: isDarkTheme ? Colors.grey[900]! : Colors.grey[200]!,
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: 4,
                    getTitlesWidget: (value, meta) {
                      final int hour = value.toInt();
                      // Ensure hour is within valid range
                      if (hour < 0 || hour > 23) return Container();
                      
                      String timeLabel;
                      
                      if (hour == 0 || hour == 24) {
                        timeLabel = '12AM';
                      } else if (hour == 12) {
                        timeLabel = '12PM';
                      } else if (hour > 12 && hour < 24) {
                        timeLabel = '${hour - 12}PM';
                      } else {
                        timeLabel = '${hour}AM';
                      }
                      
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          timeLabel,
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white70 : Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        _formatEnergyValue(value),
                        style: GoogleFonts.poppins(
                          color: isDarkTheme ? Colors.white70 : Colors.black54,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minX: 0,
              maxX: 23,
              minY: 0,
              maxY: maxY,
              lineBarsData: [
                LineChartBarData(
                  spots: _hourlyChartData,
                  isCurved: true,
                  curveSmoothness: 0.3,
                  color: Colors.blue,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotCirclePainter(
                        radius: 4,
                        color: Colors.white,
                        strokeColor: Colors.blue,
                        strokeWidth: 2,
                      );
                    },
                    checkToShowDot: (spot, barData) {
                      return spot.y > 0; // Only show dots for non-zero values
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        Colors.blue.withOpacity(0.4),
                        Colors.blue.withOpacity(0.1),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (List<LineBarSpot> touchedSpots) {
                    return touchedSpots.map((LineBarSpot touchedSpot) {
                      int hour = touchedSpot.x.toInt();
                      String timeLabel;
                      
                      if (hour == 0) {
                        timeLabel = '12:00 AM';
                      } else if (hour == 12) {
                        timeLabel = '12:00 PM';
                      } else if (hour > 12) {
                        timeLabel = '${hour - 12}:00 PM';
                      } else {
                        timeLabel = '${hour}:00 AM';
                      }
                      
                      return LineTooltipItem(
                        '$timeLabel\n${_formatEnergyValue(touchedSpot.y)}',
                        GoogleFonts.poppins(
                          color: isDarkTheme ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }).toList();
                  },
                  tooltipPadding: const EdgeInsets.all(8),
                  tooltipRoundedRadius: 8,
                ),
                touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {},
                handleBuiltInTouches: true,
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  // Build device breakdown list for any time period
  Widget _buildDeviceBreakdownList(bool isDarkTheme, {Map<String, dynamic>? deviceData, String period = 'hourly'}) {
    if (deviceData == null || deviceData.isEmpty) {
      return Center(
        child: Text(
          "no_device_data".tr(context),
          style: GoogleFonts.poppins(
            color: isDarkTheme ? Colors.white70 : Colors.black54,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    
    // Calculate total consumption for percentages
    double totalConsumption = 0.0;
    List<MapEntry<String, dynamic>> sortedDevices = [];
    
    deviceData.forEach((deviceId, data) {
      // Use the appropriate consumption field based on period
      String consumptionField = 'daily_consumption';
      if (data.containsKey('period_consumption')) {
        consumptionField = 'period_consumption';
      }
      
      double deviceConsumption = (data[consumptionField] ?? 0.0).toDouble();
      totalConsumption += deviceConsumption;
      sortedDevices.add(MapEntry(deviceId, data));
    });
    
    // Sort devices by consumption (highest first)
    sortedDevices.sort((a, b) {
      String consumptionField = 'daily_consumption';
      if (a.value.containsKey('period_consumption')) {
        consumptionField = 'period_consumption';
      }
      
      double consumptionA = (a.value[consumptionField] ?? 0.0).toDouble();
      double consumptionB = (b.value[consumptionField] ?? 0.0).toDouble();
      return consumptionB.compareTo(consumptionA);
    });
    
    // Find the device with highest consumption for tip generation
    String highestDeviceType = "";
    if (sortedDevices.isNotEmpty) {
      final highestConsumptionDevice = sortedDevices.first.value;
      
      // Try to identify device type from category ID or model name
      int categoryId = highestConsumptionDevice['category_id'] ?? 0;
      if (categoryId > 0) {
        highestDeviceType = _getCategoryName(categoryId);
      } else {
        // Try to infer from manufacturer/model
        String modelName = "${highestConsumptionDevice['model'] ?? ''}".toLowerCase();
        if (modelName.contains('fridge') || modelName.contains('refrig')) {
          highestDeviceType = 'refrigerator';
        } else if (modelName.contains('tv') || modelName.contains('television')) {
          highestDeviceType = 'tv';
        } else if (modelName.contains('washer') || modelName.contains('washing')) {
          highestDeviceType = 'washer';
        } else if (modelName.contains('ac') || modelName.contains('air')) {
          highestDeviceType = 'ac';
        } else if (modelName.contains('light') || modelName.contains('lamp')) {
          highestDeviceType = 'lighting';
        }
      }
    }
    
    // Create list items for each device
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Text(
            "device_breakdown".tr(context),
            style: GoogleFonts.poppins(
              color: isDarkTheme ? Colors.white : Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDarkTheme ? Colors.black.withOpacity(0.2) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Period summary
              Container(
                padding: const EdgeInsets.only(bottom: 12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isDarkTheme ? Colors.white24 : Colors.black12,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _getPeriodLabel(period),
                      style: GoogleFonts.poppins(
                        color: isDarkTheme ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      _formatEnergyValue(totalConsumption),
                      style: GoogleFonts.poppins(
                        color: isDarkTheme ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Device breakdown list
              ...sortedDevices.map((entry) {
                String deviceId = entry.key;
                Map<String, dynamic> deviceData = entry.value;
                
                String deviceName = "${deviceData['manufacturer'] ?? 'Unknown'} ${deviceData['model'] ?? 'Device'}";
                
                // Use the appropriate consumption field based on period
                String consumptionField = 'daily_consumption';
                if (deviceData.containsKey('period_consumption')) {
                  consumptionField = 'period_consumption';
                }
                
                double deviceConsumption = (deviceData[consumptionField] ?? 0.0).toDouble();
                double percentage = totalConsumption > 0 ? (deviceConsumption / totalConsumption) * 100 : 0;
                
                // Random color based on device ID for consistency
                Color deviceColor = Colors.primaries[deviceId.hashCode % Colors.primaries.length];
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              deviceName,
                              style: GoogleFonts.poppins(
                                color: isDarkTheme ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            "${percentage.toStringAsFixed(1)}% (${_formatEnergyValue(deviceConsumption)})",
                            style: GoogleFonts.poppins(
                              color: deviceColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percentage / 100,
                          backgroundColor: isDarkTheme ? Colors.grey[800] : Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(deviceColor),
                          minHeight: 6,
                        ),
                      ),
                      
                      // Add usage pattern if available (for hourly view)
                      if (period == 'hourly' && deviceData.containsKey('hourly_data')) ...[
                        const SizedBox(height: 8),
                        Container(
                          height: 30,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: isDarkTheme ? Colors.black26 : Colors.grey[100],
                          ),
                          child: _buildHourlyUsageIndicator(
                            deviceData['hourly_data'] as Map<String, dynamic>,
                            deviceColor,
                            isDarkTheme
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
              
              // Energy-saving tip based on the highest consumption device
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(top: 16),
                decoration: BoxDecoration(
                  color: isDarkTheme 
                      ? Colors.blue.withOpacity(0.1) 
                      : Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blue.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline, 
                          color: Colors.amber,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "energy_saving_tip".tr(context),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      // Use a direct switch statement instead of a helper method
                      (() {
                        switch (highestDeviceType.toLowerCase()) {
                          case 'refrigerator':
                          case '3':
                            return "refrigerator_tip".tr(context);
                          case 'ac':
                          case 'air conditioner':
                          case '1':
                            return "ac_tip".tr(context);
                          case 'washer':
                          case 'washing machine':
                          case '4':
                            return "washer_tip".tr(context);
                          case 'tv':
                          case '2':
                            return "tv_tip".tr(context);
                          case 'lighting':
                          case '8':
                            return "lighting_tip".tr(context);
                          default:
                            return "general_energy_tip".tr(context);
                        }
                      })(),
                      style: GoogleFonts.poppins(
                        color: isDarkTheme ? Colors.white70 : Colors.black87,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  // Add this helper method to get device-specific energy saving tips
  String _getDeviceTypeTip(String deviceType) {
    switch (deviceType.toLowerCase()) {
      case 'refrigerator':
      case '3':
        return "refrigerator_tip".tr(context);
      case 'ac':
      case 'air conditioner':
      case '1':
        return "ac_tip".tr(context);
      case 'washer':
      case 'washing machine':
      case '4':
        return "washer_tip".tr(context);
      case 'tv':
      case '2':
        return "tv_tip".tr(context);
      case 'lighting':
      case '8':
        return "lighting_tip".tr(context);
      default:
        return "general_energy_tip".tr(context);
    }
  }
  
  // Get category name from category ID
  String _getCategoryName(int categoryId) {
    switch (categoryId) {
      case 1: return 'air conditioner';
      case 2: return 'tv';
      case 3: return 'refrigerator';
      case 4: return 'washer';
      case 5: return 'microwave';
      case 6: return 'oven';
      case 7: return 'water heater';
      case 8: return 'lighting';
      case 9: return 'computer';
      case 10: return 'vacuum';
      default: return '';
    }
  }

  // Helper to build hourly usage pattern indicator
  Widget _buildHourlyUsageIndicator(Map<String, dynamic> hourlyData, Color color, bool isDarkTheme) {
    List<int> hours = hourlyData.keys
        .map((k) => int.tryParse(k) ?? 0)
        .where((h) => h >= 0 && h < 24)
        .toList();
    
    if (hours.isEmpty) return Container();
    
    // Find max value for normalization
    double maxValue = 0;
    hours.forEach((hour) {
      double value = (hourlyData[hour.toString()] as num).toDouble();
      if (value > maxValue) maxValue = value;
    });
    
    return Row(
      children: List.generate(24, (hour) {
        double value = 0;
        if (hourlyData.containsKey(hour.toString())) {
          value = (hourlyData[hour.toString()] as num).toDouble();
        }
        
        // Normalize height (0.2 min height for visibility if there's any usage)
        double normalizedHeight = maxValue > 0 
            ? (value > 0 ? 0.2 + (value / maxValue) * 0.8 : 0) 
            : 0;
        
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            alignment: Alignment.bottomCenter,
            child: Container(
              height: normalizedHeight * 30,
              decoration: BoxDecoration(
                color: color.withOpacity(0.7),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(2),
                  topRight: Radius.circular(2),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  // Return a period label based on the time period
  String _getPeriodLabel(String period) {
    switch (period) {
      case 'hourly':
        return "Hourly Breakdown";
      case 'daily':
        return "Daily Breakdown";
      case 'weekly':
        return "Weekly Breakdown";
      case 'monthly':
        return "Monthly Breakdown";
      default:
        return "Energy Breakdown";
    }
  }

  // Build energy saving tip based on period
  Widget _buildEnergySavingTip(bool isDarkTheme, String period) {
    String tipText = "";
    IconData tipIcon = Icons.lightbulb_outline;
    
    switch (period) {
      case 'hourly':
        tipText = _getEnergySavingTip();
        break;
      case 'daily':
        tipText = "daily_energy_tip".tr(context);
        tipIcon = Icons.eco_outlined;
        break;
      case 'weekly':
        tipText = "weekly_energy_tip".tr(context);
        tipIcon = Icons.trending_down;
        break;
      case 'monthly':
        tipText = "monthly_energy_tip".tr(context);
        tipIcon = Icons.insights;
        break;
      default:
        tipText = "general_energy_tip".tr(context);
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: isDarkTheme 
            ? Colors.blue.withOpacity(0.1) 
            : Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.blue.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                tipIcon, 
                color: Colors.amber,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                "energy_saving_tip".tr(context),
                style: GoogleFonts.poppins(
                  color: isDarkTheme ? Colors.white : Colors.black,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tipText,
            style: GoogleFonts.poppins(
              color: isDarkTheme ? Colors.white70 : Colors.black87,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // Add this method to get period-specific device data
  Future<Map<String, dynamic>> _getPeriodDeviceData() async {
    try {
      String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (userId.isEmpty) return {};
      
      Map<String, dynamic> deviceData = {};
      
      switch (_selectedPeriod) {
        case 'hourly':
          // For hourly, use the existing hourly device data
          if (_deviceBreakdownData.isNotEmpty) {
            return _deviceBreakdownData;
          }
          
          // If we don't have it, load it
          if (_selectedDate.isNotEmpty) {
            Map<String, dynamic> enhancedData = 
                await DatabaseHelper.instance.getHourlyConsumptionEnhanced(userId, _selectedDate);
            return enhancedData['devices_data'] ?? {};
          }
          break;
          
        case 'daily':
        case 'weekly':
        case 'monthly':
          // For these periods, aggregate device data across the period
          deviceData = await _calculatePeriodDeviceData(userId);
          break;
      }
      
      return deviceData;
    } catch (e) {
      developer.log("Error getting period device data: $e");
      return {};
    }
  }
  
  // Calculate aggregated device data for a period
  Future<Map<String, dynamic>> _calculatePeriodDeviceData(String userId) async {
    Map<String, dynamic> aggregatedDeviceData = {};
    
    try {
      // Get date range
      DateTime startDate = _startDate ?? DateTime.now().subtract(const Duration(days: 30));
      DateTime endDate = _endDate ?? DateTime.now();
      
      // Get all consumption records for the period
      List<Map<String, dynamic>> periodData = await DatabaseHelper.instance.getDailyConsumption(
        userId, startDate, endDate
      );
      
      // Get device info to add to results
      List<Map<String, dynamic>> userDevices = await DatabaseHelper.instance.getDevices(userId);
      Map<String, Map<String, dynamic>> deviceInfo = {};
      for (var device in userDevices) {
        deviceInfo[device['id']] = {
          'manufacturer': device['manufacturer'] ?? 'Unknown',
          'model': device['model'] ?? 'Device',
          'category_id': device['category_id'] ?? 0,
        };
      }
      
      // Process all consumption records and aggregate by device
      for (var record in periodData) {
        if (record.containsKey('devices_consumption')) {
          Map<String, dynamic> devices = Map<String, dynamic>.from(record['devices_consumption']);
          
          devices.forEach((deviceId, data) {
            if (!aggregatedDeviceData.containsKey(deviceId)) {
              // Initialize device data
              aggregatedDeviceData[deviceId] = {
                'manufacturer': data['manufacturer'] ?? deviceInfo[deviceId]?['manufacturer'] ?? 'Unknown',
                'model': data['model'] ?? deviceInfo[deviceId]?['model'] ?? 'Device',
                'period_consumption': 0.0,
              };
            }
            
            // Add this day's consumption to the total
            double dailyConsumption = (data['daily_consumption'] ?? 0.0).toDouble();
            aggregatedDeviceData[deviceId]['period_consumption'] = 
                (aggregatedDeviceData[deviceId]['period_consumption'] ?? 0.0) + dailyConsumption;
          });
        }
      }
      
      return aggregatedDeviceData;
    } catch (e) {
      developer.log("Error calculating period device data: $e");
      return {};
    }
  }

  // Update _buildHistoryContent to include device breakdown for all periods
  Widget _buildHistoryContent(List<FlSpot> chartData, List<String> dates, double totalPeriodConsumption, bool isDarkTheme, {bool isHourlyView = false, List<dynamic> docs = const []}) {
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
              _buildPeriodButton("Hourly", _selectedPeriod == 'hourly', isDarkTheme),
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
        
        // Add a FutureBuilder here to show device breakdown for all periods
        FutureBuilder<Map<String, dynamic>>(
          future: _getPeriodDeviceData(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 30.0),
                  child: CircularProgressIndicator(color: Colors.blueAccent),
                ),
              );
            }
            
            Map<String, dynamic> deviceData = snapshot.data ?? {};
            
            return _buildDeviceBreakdownList(
              isDarkTheme, 
              deviceData: deviceData,
              period: _selectedPeriod
            );
          },
        ),
        
        const SizedBox(height: 25),
        
        // Show list of daily details only for daily view
        if (_selectedPeriod == 'daily') ...[
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
            itemCount: docs.length,
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
                child: InkWell(
                  onTap: () => _showHourlyDetail(dateStr, isDarkTheme),
                  borderRadius: BorderRadius.circular(12),
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
                    trailing: Icon(
                      Icons.bar_chart,
                      color: isDarkTheme ? Colors.blue[300] : Colors.blue[700],
                    ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                            // Added: Show device breakdown for this specific day
                            if (data.containsKey('devices_consumption') && 
                                (data['devices_consumption'] as Map).isNotEmpty) ...[
                                    Text(
                                "device_breakdown".tr(context),
                                      style: GoogleFonts.poppins(
                                        color: isDarkTheme ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.w500,
                                        fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...buildDeviceBreakdownListForDay(
                                data['devices_consumption'] != null 
                                  ? (data['devices_consumption'] as Map<String, dynamic>) 
                                  : <String, dynamic>{},
                                consumption,
                                isDarkTheme
                              ),
                              const SizedBox(height: 8),
                            ],
                            // Added: Energy saving tip based on the day's consumption
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: isDarkTheme 
                                    ? Colors.blue.withOpacity(0.1) 
                                    : Colors.blue.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.blue.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.lightbulb_outline, 
                                        color: Colors.amber,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        "energy_saving_tip".tr(context),
                                        style: GoogleFonts.poppins(
                                          color: isDarkTheme ? Colors.white : Colors.black,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    // Get tip based on device breakdown - use original data
                                    _getTipForDailyConsumption(data['devices_consumption'] != null 
                                      ? (data['devices_consumption'] as Map<String, dynamic>) 
                                      : <String, dynamic>{}),
                                    style: GoogleFonts.poppins(
                                      color: isDarkTheme ? Colors.white70 : Colors.black87,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                                      ),
                                    ),
                                    Divider(color: isDarkTheme ? Colors.white30 : Colors.black12),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: () => _showHourlyDetail(dateStr, isDarkTheme),
                              icon: Icon(Icons.access_time, size: 16),
                              label: Text("view_hourly_breakdown".tr(context)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                            ),
                                  ],
                                ),
                              ),
                            ],
                  ),
                          ),
                        );
                      },
                    ),
        ],
      ],
    );
  }

  // Custom method to format data for weekly and monthly views
  void _createCustomFormattedData(List<QueryDocumentSnapshot> docs, bool isDarkTheme) {
    List<FlSpot> chartData = [];
    List<String> customLabels = [];
    double totalPeriodConsumption = 0.0;
    
    if (_selectedPeriod == 'weekly') {
      // For weekly view, create custom week ranges like "MAY 1-7"
      Map<String, double> weeklyData = {};
      Map<String, String> weekLabels = {};
      
      // First, get all the consumption data
      for (var doc in docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        DateTime date = DateTime.parse(data['date'] ?? doc.id);
        
        // Calculate which week this belongs to
        DateTime firstDayOfYear = DateTime(date.year, 1, 1);
        int dayOfYear = date.difference(firstDayOfYear).inDays;
        int weekNum = (dayOfYear ~/ 7) + 1;
        String weekKey = "${date.year}-W$weekNum";
        
        // Add consumption to weekly total
        weeklyData[weekKey] = (weeklyData[weekKey] ?? 0.0) + (data['total_consumption']?.toDouble() ?? 0.0);
        
        // Create a label for this week if we don't have one yet
        if (!weekLabels.containsKey(weekKey)) {
          // Approximate week start and end
          DateTime weekStart = firstDayOfYear.add(Duration(days: (weekNum - 1) * 7));
          DateTime weekEnd = weekStart.add(const Duration(days: 6));
          
          // Format as "MAY 1-7"
          String monthName = DateFormat('MMM').format(weekStart).toUpperCase();
          String label = '$monthName ${weekStart.day}-${weekEnd.day}';
          weekLabels[weekKey] = label;
        }
        
        totalPeriodConsumption += (data['total_consumption']?.toDouble() ?? 0.0);
      }
      
      // Sort the weeks
      List<String> sortedWeeks = weeklyData.keys.toList()
        ..sort((a, b) {
          int yearA = int.parse(a.split('-W')[0]);
          int yearB = int.parse(b.split('-W')[0]);
          int weekA = int.parse(a.split('-W')[1]);
          int weekB = int.parse(b.split('-W')[1]);
          
          if (yearA != yearB) return yearA.compareTo(yearB);
          return weekA.compareTo(weekB);
        });
      
      // Create chart data points and labels
      for (int i = 0; i < sortedWeeks.length; i++) {
        String weekKey = sortedWeeks[i];
        chartData.add(FlSpot(i.toDouble(), weeklyData[weekKey]!));
        customLabels.add(weekLabels[weekKey]!);
      }
    } else if (_selectedPeriod == 'monthly') {
      // For monthly view, create month labels like "APRIL", "MAY", etc.
      Map<String, double> monthlyData = {};
      
      // First, get all the consumption data
      for (var doc in docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        DateTime date = DateTime.parse(data['date'] ?? doc.id);
        String monthKey = DateFormat('yyyy-MM').format(date);
        
        // Add consumption to monthly total
        monthlyData[monthKey] = (monthlyData[monthKey] ?? 0.0) + (data['total_consumption']?.toDouble() ?? 0.0);
        
        totalPeriodConsumption += (data['total_consumption']?.toDouble() ?? 0.0);
      }
      
      // Sort the months
      List<String> sortedMonths = monthlyData.keys.toList()..sort();
      
      // Create chart data points and month name labels
      for (int i = 0; i < sortedMonths.length; i++) {
        String monthKey = sortedMonths[i];
        chartData.add(FlSpot(i.toDouble(), monthlyData[monthKey]!));
        
        // Format as "APRIL"
        DateTime date = DateTime.parse('${monthKey}-01');
        customLabels.add(DateFormat('MMM').format(date).toUpperCase());
      }
    }
    
    // Store formatted data for use in the chart
    _chartData = chartData;
    _dateLabels = customLabels;
  }

  // Show detailed hourly view for a specific date
  void _showHourlyDetail(String date, bool isDarkTheme) {
    _loadHourlyData(date);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              color: isDarkTheme ? const Color(0xFF1A1F38) : Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(25),
                topRight: Radius.circular(25),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(51),
                  blurRadius: 10,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Modal header with title and close button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('EEEE, MMM d, yyyy').format(DateTime.parse(date)),
                            style: GoogleFonts.poppins(
                              color: isDarkTheme ? Colors.white : Colors.black,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            "hourly_energy_usage".tr(context),
                            style: GoogleFonts.poppins(
                              color: isDarkTheme ? Colors.white70 : Colors.black54,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: isDarkTheme ? Colors.white70 : Colors.black54,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // Main content (scrollable)
                  Expanded(
                    child: _isLoading 
                      ? Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                          child: Column(
                            children: [
                              // Hourly chart
                              _buildHourlyConsumptionChart(isDarkTheme),
                              
                              // Energy consumption tips
                              if (!_isLoading && _hourlyData.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: isDarkTheme 
                                        ? Colors.blue.withOpacity(0.1) 
                                        : Colors.blue.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.blue.withOpacity(0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.lightbulb_outline, 
                                            color: Colors.amber,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            "energy_saving_tip".tr(context),
        style: GoogleFonts.poppins(
                                              color: isDarkTheme ? Colors.white : Colors.black,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _getEnergySavingTip(),
                                        style: GoogleFonts.poppins(
                                          color: isDarkTheme ? Colors.white70 : Colors.black87,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                  ),
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  // Get energy saving tip based on hourly consumption pattern
  String _getEnergySavingTip() {
    // Find peak hour
    int peakHour = 0;
    double peakConsumption = 0;
    
    _hourlyData.forEach((hour, consumption) {
      if (consumption > peakConsumption) {
        peakConsumption = consumption;
        peakHour = hour;
      }
    });
    
    // Tips based on time of day
    if (peakHour >= 17 && peakHour <= 21) {
      return "evening_peak_tip".tr(context);
    } else if (peakHour >= 6 && peakHour <= 9) {
      return "morning_peak_tip".tr(context);
    } else if (peakHour >= 12 && peakHour <= 14) {
      return "midday_peak_tip".tr(context);
    } else {
      return "general_energy_tip".tr(context);
    }
  }

  // Add these new helper methods to support the daily breakdown enhancements
  
  // Build device breakdown list for a specific day
  List<Widget> buildDeviceBreakdownListForDay(
    Map<String, dynamic> devicesConsumption, 
    double totalConsumption,
    bool isDarkTheme
  ) {
    if (devicesConsumption.isEmpty) {
      return [
        Text(
          "no_device_data".tr(context),
                    style: GoogleFonts.poppins(
            color: isDarkTheme ? Colors.white70 : Colors.black54,
            fontStyle: FontStyle.italic,
                      fontSize: 12,
                    ),
        )
      ];
    }
    
    // Sort devices by consumption (highest first)
    List<MapEntry<String, dynamic>> sortedDevices = devicesConsumption.entries.toList();
    sortedDevices.sort((a, b) {
      double valueA = (a.value['daily_consumption'] ?? 0.0).toDouble();
      double valueB = (b.value['daily_consumption'] ?? 0.0).toDouble();
      return valueB.compareTo(valueA);
    });
    
    // Create list items for each device (display top 3 for clarity)
    List<Widget> deviceWidgets = [];
    int maxToShow = sortedDevices.length > 3 ? 3 : sortedDevices.length;
    
    for (int i = 0; i < maxToShow; i++) {
      String deviceId = sortedDevices[i].key;
      Map<String, dynamic> data = sortedDevices[i].value;
      String deviceName = "${data['manufacturer'] ?? 'Unknown'} ${data['model'] ?? 'Device'}";
      double consumption = (data['daily_consumption'] ?? 0.0).toDouble();
      double percentage = totalConsumption > 0 ? (consumption / totalConsumption) * 100 : 0;
      
      // Add device row
      deviceWidgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  deviceName,
                  style: GoogleFonts.poppins(
                    color: isDarkTheme ? Colors.white70 : Colors.black87,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 1,
                child: LinearProgressIndicator(
                  value: percentage / 100,
                  backgroundColor: isDarkTheme ? Colors.grey[800] : Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.primaries[deviceId.hashCode % Colors.primaries.length],
                  ),
                  minHeight: 5,
                ),
              ),
              SizedBox(width: 10),
              Text(
                "${percentage.toStringAsFixed(1)}%",
                style: GoogleFonts.poppins(
                  color: isDarkTheme ? Colors.white : Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
            ),
          ),
        ],
          ),
      ),
    );
  }
    
    // If there are more devices, add a "more" indicator
    if (sortedDevices.length > 3) {
      deviceWidgets.add(
        Text(
          "+ ${sortedDevices.length - 3} more devices",
          style: GoogleFonts.poppins(
            color: isDarkTheme ? Colors.white54 : Colors.black45,
            fontSize: 11,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    
    return deviceWidgets;
  }

  // Generate energy saving tip based on device consumption pattern
  String _getTipForDailyConsumption(Map<String, dynamic> devicesConsumption) {
    if (devicesConsumption.isEmpty) {
      return "general_energy_tip".tr(context);
    }
    
    // Check if we're getting a pre-identified device type
    if (devicesConsumption.containsKey('highest_device') && 
        devicesConsumption['highest_device'].containsKey('category_type')) {
      String deviceType = devicesConsumption['highest_device']['category_type'];
      
      // Inline the tip selection logic
      switch (deviceType.toLowerCase()) {
        case 'refrigerator':
        case '3':
          return "refrigerator_tip".tr(context);
        case 'ac':
        case 'air conditioner':
        case '1':
          return "ac_tip".tr(context);
        case 'washer':
        case 'washing machine':
        case '4':
          return "washer_tip".tr(context);
        case 'tv':
        case '2':
          return "tv_tip".tr(context);
        case 'lighting':
        case '8':
          return "lighting_tip".tr(context);
        default:
          return "general_energy_tip".tr(context);
      }
    }
    
    // Original logic for finding highest consumption device
    String highestDeviceType = "";
    double highestConsumption = 0;
    
    devicesConsumption.forEach((deviceId, data) {
      double consumption = (data['daily_consumption'] ?? 0.0).toDouble();
      if (consumption > highestConsumption) {
        highestConsumption = consumption;
        
        // Try to identify device type from data
        int categoryId = data['category_id'] ?? 0;
        if (categoryId > 0) {
          highestDeviceType = _getCategoryName(categoryId);
        } else {
          // Try to infer from manufacturer/model
          String modelName = "${data['model'] ?? ''}".toLowerCase();
          if (modelName.contains('fridge') || modelName.contains('refrig')) {
            highestDeviceType = 'refrigerator';
          } else if (modelName.contains('tv') || modelName.contains('television')) {
            highestDeviceType = 'tv';
          } else if (modelName.contains('washer') || modelName.contains('washing')) {
            highestDeviceType = 'washer';
          } else if (modelName.contains('ac') || modelName.contains('air')) {
            highestDeviceType = 'ac';
          }
        }
      }
    });
    
    // Inline the tip selection logic again
    switch (highestDeviceType.toLowerCase()) {
      case 'refrigerator':
      case '3':
        return "refrigerator_tip".tr(context);
      case 'ac':
      case 'air conditioner':
      case '1':
        return "ac_tip".tr(context);
      case 'washer':
      case 'washing machine':
      case '4':
        return "washer_tip".tr(context);
      case 'tv':
      case '2':
        return "tv_tip".tr(context);
      case 'lighting':
      case '8':
        return "lighting_tip".tr(context);
      default:
        return "general_energy_tip".tr(context);
    }
  }
}

