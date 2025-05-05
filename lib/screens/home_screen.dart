import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:energenius/database/database_helper.dart';
import 'package:energenius/screens/login_screen.dart';
import 'dart:developer';
import '../theme_provider.dart';
import '../utils/conversion_utilities.dart';
import '../localization/app_localizations.dart';
import 'package:fl_chart/fl_chart.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late AnimationController _animationController;
  late Animation<double> _fadeInAnimation;
  
  User? user;
  String firstName = "User";
  String country = "Unknown";
  double totalDailyConsumption = 0.0;
  bool isLoading = true;
  String _currency = 'EGP';
  String _energyUnit = 'kWh';
  double _estimatedBill = 0.0;
  final double _pricePerUnit = 1.2; // Example price per kWh

  @override
  void initState() {
    super.initState();
    
    // Setup animations
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    
    _fadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn)
    );
    
    _loadUserData();
    _loadSettings();
    _calculateEstimatedBill();
    
    _animationController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Rebuild the UI when locale changes
    AppLocalizations.of(context);
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      user = _auth.currentUser;
      if (user == null) {
        log("No user logged in");
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
        return;
      }

      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();
      log("Firestore user data: ${userDoc.data()}");

      if (userDoc.exists) {
        Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;
        firstName = data['first_name'] ?? "User";
        country = data['country'] ?? "Unknown";
        log("User data loaded: firstName=$firstName, country=$country");
      } else {
        log("User document does not exist in Firestore for UID: ${user!.uid}");
        await FirebaseFirestore.instance.collection('users').doc(user!.uid).set({
          'first_name': "User",
          'country': "Unknown",
          'uid': user!.uid,
        });
        log("Created user document for UID: ${user!.uid}");
      }

      try {
        List<Map<String, dynamic>> devices = await DatabaseHelper.instance.getUserDevices(user!.uid);
        double total = 0.0;
        for (var device in devices) {
          double powerConsumption = (device['power_consumption'] ?? 0.0).toDouble();
          double usageHours = (device['usage_hours_per_day'] ?? 0.0).toDouble();
          total += powerConsumption * usageHours;
        }
        totalDailyConsumption = total;
        _calculateEstimatedBill();
        log("User-added devices loaded: $devices, Total consumption: $totalDailyConsumption");
      } catch (e) {
        log("Error loading devices: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error loading devices: $e", style: const TextStyle(color: Colors.white)),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      log("Error loading user data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error loading data: $e", style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _currency = prefs.getString('currency') ?? 'EGP';
        _energyUnit = prefs.getString('energyUnit') ?? 'kWh';
        _calculateEstimatedBill();
      });
    }
  }

  void _calculateEstimatedBill() {
    // Simple calculation for monthly bill based on daily consumption * 30 days * price per unit
    // We always calculate the bill in kWh since that's the standard pricing unit
    _estimatedBill = totalDailyConsumption * 30 * _pricePerUnit;
  }

  // Format the bill amount using the utility class
  String _getFormattedBill() {
    // Convert the bill amount from EGP to the selected currency
    double convertedAmount = _estimatedBill;
    if (_currency != 'EGP') {
      convertedAmount = ConversionUtilities.convertCurrency(_estimatedBill, 'EGP', _currency);
    }
    
    // Format with the appropriate currency symbol
    String symbol = ConversionUtilities.currencySymbols[_currency] ?? _currency;
    if (_currency == 'EGP') {
      return "${convertedAmount.toStringAsFixed(2)} $_currency";
    } else {
      return "$symbol ${convertedAmount.toStringAsFixed(2)}";
    }
  }
  
  // Convert an energy value to the selected unit
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

  Future<void> _saveCurrency(String newCurrency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currency', newCurrency);
    setState(() {
      _currency = newCurrency;
      _calculateEstimatedBill(); // Recalculate with new currency
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Currency updated to $_currency!", style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }

  Future<void> _saveEnergyUnit(String newEnergyUnit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('energyUnit', newEnergyUnit);
    setState(() {
      _energyUnit = newEnergyUnit;
      _calculateEstimatedBill(); // Recalculate with new energy unit
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Energy unit updated to $_energyUnit!", style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }

  void _logout() async {
    await _auth.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  void _showEnergyBillDetails() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final bool isDarkTheme = themeProvider.isDarkTheme;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
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
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Modal title with close button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "energy_bill_details".tr(context),
                      style: GoogleFonts.poppins(
                        color: isDarkTheme ? Colors.white : Colors.black,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
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
                
                // Bill Summary Card - Restored from previous design
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDarkTheme
                          ? [Colors.blue[800]!, Colors.blue[900]!]
                          : [Colors.blue[400]!, Colors.blue[600]!],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withAlpha(77),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "estimated_monthly_bill".tr(context),
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(51),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              "Pending",
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _getFormattedBill(),
                        style: GoogleFonts.poppins(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "based_on_monthly_usage".trParams(context, [_formatEnergyValue(totalDailyConsumption * 30)]),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.white.withAlpha(230),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                
                Text(
                  "monthly_consumption".tr(context),
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDarkTheme ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 15),
                SizedBox(
                  height: 200,
                  child: _buildSimpleLineChart(isDarkTheme),
                ),
                const SizedBox(height: 30),
                
                // Energy consumption details
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDarkTheme ? Colors.white.withAlpha(26) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "consumption_details".tr(context),
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          color: isDarkTheme ? Colors.white : Colors.black,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "daily".tr(context),
                            style: GoogleFonts.poppins(
                              color: isDarkTheme ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          Text(
                            _formatEnergyValue(totalDailyConsumption),
                            style: GoogleFonts.poppins(
                              color: isDarkTheme ? Colors.white : Colors.black,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 25),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "weekly".tr(context),
                            style: GoogleFonts.poppins(
                              color: isDarkTheme ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          Text(
                            _formatEnergyValue(totalDailyConsumption * 7),
                            style: GoogleFonts.poppins(
                              color: isDarkTheme ? Colors.white : Colors.black,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 25),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "monthly".tr(context),
                            style: GoogleFonts.poppins(
                              color: isDarkTheme ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          Text(
                            _formatEnergyValue(totalDailyConsumption * 30),
                            style: GoogleFonts.poppins(
                              color: isDarkTheme ? Colors.white : Colors.black,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 25),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "yearly".tr(context),
                            style: GoogleFonts.poppins(
                              color: isDarkTheme ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          Text(
                            _formatEnergyValue(totalDailyConsumption * 365),
                            style: GoogleFonts.poppins(
                              color: isDarkTheme ? Colors.white : Colors.black,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Current settings
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDarkTheme ? Colors.white.withAlpha(26) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "settings".tr(context),
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          color: isDarkTheme ? Colors.white : Colors.black,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "energy_unit".tr(context),
                            style: GoogleFonts.poppins(
                              color: isDarkTheme ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                _energyUnit,
                                style: GoogleFonts.poppins(
                                  color: isDarkTheme ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: Colors.blueAccent,
                                ),
                                onPressed: () {
                                  Navigator.pop(context);
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      backgroundColor: isDarkTheme 
                                          ? const Color(0xFF1A1F38) 
                                          : Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                      title: Text(
                                        "select_energy_unit".tr(context),
                                        style: GoogleFonts.poppins(
                                          color: isDarkTheme ? Colors.white : Colors.black,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      content: DropdownButton<String>(
                                        value: _energyUnit,
                                        dropdownColor: isDarkTheme 
                                            ? const Color(0xFF1A1F38) 
                                            : Colors.white,
                                        style: GoogleFonts.poppins(
                                          color: isDarkTheme ? Colors.white : Colors.black,
                                        ),
                                        items: ConversionUtilities.energyConversions.keys
                                            .map<DropdownMenuItem<String>>((String value) {
                                          return DropdownMenuItem<String>(
                                            value: value,
                                            child: Text(value),
                                          );
                                        }).toList(),
                                        onChanged: (String? newValue) {
                                          if (newValue != null) {
                                            _saveEnergyUnit(newValue);
                                            Navigator.pop(context);
                                            // Reopen the bill details after changing unit
                                            _showEnergyBillDetails();
                                          }
                                        },
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Divider(height: 25),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "currency".tr(context),
                            style: GoogleFonts.poppins(
                              color: isDarkTheme ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                _currency,
                                style: GoogleFonts.poppins(
                                  color: isDarkTheme ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: Colors.blueAccent,
                                ),
                                onPressed: () {
                                  Navigator.pop(context);
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      backgroundColor: isDarkTheme 
                                          ? const Color(0xFF1A1F38) 
                                          : Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                      title: Text(
                                        "select_currency".tr(context),
                                        style: GoogleFonts.poppins(
                                          color: isDarkTheme ? Colors.white : Colors.black,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      content: DropdownButton<String>(
                                        value: _currency,
                                        dropdownColor: isDarkTheme 
                                            ? const Color(0xFF1A1F38) 
                                            : Colors.white,
                                        style: GoogleFonts.poppins(
                                          color: isDarkTheme ? Colors.white : Colors.black,
                                        ),
                                        items: ConversionUtilities.currencyRates.keys
                                            .map<DropdownMenuItem<String>>((String value) {
                                          return DropdownMenuItem<String>(
                                            value: value,
                                            child: Text("$value (${ConversionUtilities.currencySymbols[value] ?? value})"),
                                          );
                                        }).toList(),
                                        onChanged: (String? newValue) {
                                          if (newValue != null) {
                                            _saveCurrency(newValue);
                                            Navigator.pop(context);
                                            // Reopen the bill details after changing currency
                                            _showEnergyBillDetails();
                                          }
                                        },
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Coming Soon Notice
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDarkTheme ? Colors.grey[800]!.withAlpha(77) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDarkTheme ? Colors.blue[700]! : Colors.blue[300]!,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: isDarkTheme ? Colors.blue[300] : Colors.blue[700],
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Bill payment feature coming soon! Monitor your energy usage to reduce costs.",
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: isDarkTheme ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Add bottom padding
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildSimpleLineChart(bool isDarkTheme) {
    // Handle case where consumption is zero or very small
    final double effectiveConsumption = totalDailyConsumption <= 0.1 ? 1.0 : totalDailyConsumption;
    
    // Sample data for demonstration
    final List<FlSpot> spots = [
      FlSpot(0, effectiveConsumption * 0.85),
      FlSpot(1, effectiveConsumption * 0.95),
      FlSpot(2, effectiveConsumption * 1.1),
      FlSpot(3, effectiveConsumption * 0.9),
      FlSpot(4, effectiveConsumption * 1.05),
      FlSpot(5, effectiveConsumption * 1.1),
      FlSpot(6, effectiveConsumption),
    ];
    
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: effectiveConsumption / 4 > 0 ? effectiveConsumption / 4 : 0.25,
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
                const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                final int index = value.toInt();
                if (index >= 0 && index < days.length) {
                  return Text(
                    days[index],
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
                // Convert value to the selected energy unit for display
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
        maxX: 6,
        minY: 0,
        maxY: effectiveConsumption * 1.5,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
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

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool isDarkTheme = themeProvider.isDarkTheme;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        height: screenHeight,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDarkTheme
                ? [Colors.blueAccent.withAlpha(51), const Color(0xFF0D1117)]
                : [Colors.white, Colors.grey[200]!],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
                : FadeTransition(
                    opacity: _fadeInAnimation,
                    child: RefreshIndicator(
                      onRefresh: () async {
                        await _loadUserData();
                      },
                      color: Colors.blueAccent,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: screenHeight - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom - 32,
                            minWidth: screenWidth,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "${("welcome".tr(context))}, $firstName!",
                                    style: GoogleFonts.poppins(
                                      color: isDarkTheme ? Colors.white : Colors.black,
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.logout, color: Colors.redAccent),
                                    onPressed: _logout,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(
                                    Icons.location_on,
                                    size: 16,
                                    color: isDarkTheme ? Colors.blue[300] : Colors.blue,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    country,
                                    style: GoogleFonts.poppins(
                                      color: isDarkTheme ? Colors.white70 : Colors.black87,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 30),
                              // Energy Overview Card
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: isDarkTheme ? Colors.white.withAlpha(19) : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(26),
                                      blurRadius: 15,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: isDarkTheme 
                                                ? Colors.blue.withAlpha(51) 
                                                : Colors.blue.withAlpha(26),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            Icons.electric_bolt,
                                            color: Colors.blue[600],
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 15),
                                        Text(
                                          "energy_overview".tr(context),
                                          style: GoogleFonts.poppins(
                                            color: isDarkTheme ? Colors.white : Colors.black,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    _buildConsumptionInfo(isDarkTheme),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 30),
                              Text(
                                "quick_actions".tr(context),
                                style: GoogleFonts.poppins(
                                  color: isDarkTheme ? Colors.white : Colors.black,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 15),
                              GridView.count(
                                crossAxisCount: 2,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                crossAxisSpacing: 15,
                                mainAxisSpacing: 15,
                                childAspectRatio: 1.5,
                                children: [
                                  _buildActionCard(
                                    title: "energy_bill".tr(context),
                                    icon: Icons.receipt_long,
                                    color: Colors.deepPurple,
                                    isDarkTheme: isDarkTheme,
                                    onTap: _showEnergyBillDetails,
                                  ),
                                  _buildActionCard(
                                    title: "set_currency".tr(context),
                                    icon: Icons.attach_money,
                                    color: Colors.green,
                                    isDarkTheme: isDarkTheme,
                                    onTap: () {
                                      showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          backgroundColor: isDarkTheme 
                                              ? const Color(0xFF1A1F38) 
                                              : Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                          title: Text(
                                            "select_currency".tr(context),
                                            style: GoogleFonts.poppins(
                                              color: isDarkTheme ? Colors.white : Colors.black,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          content: DropdownButton<String>(
                                            value: _currency,
                                            dropdownColor: isDarkTheme 
                                                ? const Color(0xFF1A1F38) 
                                                : Colors.white,
                                            style: GoogleFonts.poppins(
                                              color: isDarkTheme ? Colors.white : Colors.black,
                                            ),
                                            items: ConversionUtilities.currencyRates.keys
                                                .map<DropdownMenuItem<String>>((String value) {
                                              return DropdownMenuItem<String>(
                                                value: value,
                                                child: Text("$value (${ConversionUtilities.currencySymbols[value] ?? value})"),
                                              );
                                            }).toList(),
                                            onChanged: (String? newValue) {
                                              if (newValue != null) {
                                                _saveCurrency(newValue);
                                                Navigator.pop(context);
                                              }
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  _buildActionCard(
                                    title: "energy_tips".tr(context),
                                    icon: Icons.lightbulb_outlined,
                                    color: Colors.orange,
                                    isDarkTheme: isDarkTheme,
                                    onTap: () {
                                      // Will be implemented later
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            "energy_tips_coming_soon".tr(context),
                                            style: GoogleFonts.poppins(color: Colors.white),
                                          ),
                                          backgroundColor: Colors.blue[800],
                                        ),
                                      );
                                    },
                                  ),
                                  _buildActionCard(
                                    title: "set_energy_unit".tr(context),
                                    icon: Icons.power,
                                    color: Colors.purple,
                                    isDarkTheme: isDarkTheme,
                                    onTap: () {
                                      showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          backgroundColor: isDarkTheme 
                                              ? const Color(0xFF1A1F38) 
                                              : Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                          title: Text(
                                            "select_energy_unit".tr(context),
                                            style: GoogleFonts.poppins(
                                              color: isDarkTheme ? Colors.white : Colors.black,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          content: DropdownButton<String>(
                                            value: _energyUnit,
                                            dropdownColor: isDarkTheme 
                                                ? const Color(0xFF1A1F38) 
                                                : Colors.white,
                                            style: GoogleFonts.poppins(
                                              color: isDarkTheme ? Colors.white : Colors.black,
                                            ),
                                            items: ConversionUtilities.energyConversions.keys
                                                .map<DropdownMenuItem<String>>((String value) {
                                              return DropdownMenuItem<String>(
                                                value: value,
                                                child: Text(value),
                                              );
                                            }).toList(),
                                            onChanged: (String? newValue) {
                                              if (newValue != null) {
                                                _saveEnergyUnit(newValue);
                                                Navigator.pop(context);
                                              }
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  _buildActionCard(
                                    title: "settings".tr(context),
                                    icon: Icons.settings,
                                    color: Colors.blueGrey,
                                    isDarkTheme: isDarkTheme,
                                    onTap: () {
                                      // Navigate to settings
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 80), // Padding for navigation bar
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required IconData icon,
    required Color color,
    required bool isDarkTheme,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDarkTheme ? Colors.white.withAlpha(13) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: isDarkTheme 
                  ? Colors.black.withAlpha(51) 
                  : Colors.grey.withAlpha(26),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withAlpha(isDarkTheme ? 51 : 26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: isDarkTheme ? Colors.white : Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConsumptionInfo(bool isDarkTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main consumption card - Shows current real-time consumption
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDarkTheme
                  ? [Colors.blue[700]!, Colors.blue[900]!]
                  : [Colors.blue[400]!, Colors.blue[600]!],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withAlpha(77),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "current_consumption".tr(context),
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 15),
              Text(
                _formatEnergyValue(totalDailyConsumption / 24), // Real-time consumption approximation
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${("estimated_bill".tr(context))}: ${_getFormattedBill()}",
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.white.withAlpha(230),
                    ),
                  ),
                  GestureDetector(
                    onTap: _showEnergyBillDetails,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(51),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Text(
                            "details".tr(context),
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.white,
                            size: 12,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        
        // Energy statistics row with daily, weekly, monthly
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: "daily".tr(context),
                value: _formatEnergyValue(totalDailyConsumption),
                iconData: Icons.today,
                isDarkTheme: isDarkTheme,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildStatCard(
                title: "weekly".tr(context),
                value: _formatEnergyValue(totalDailyConsumption * 7),
                iconData: Icons.calendar_view_week,
                isDarkTheme: isDarkTheme,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildStatCard(
                title: "monthly".tr(context),
                value: _formatEnergyValue(totalDailyConsumption * 30),
                iconData: Icons.calendar_month,
                isDarkTheme: isDarkTheme,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData iconData,
    required bool isDarkTheme,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkTheme ? Colors.white.withAlpha(26) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                iconData,
                color: isDarkTheme ? Colors.white70 : Colors.black54,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: isDarkTheme ? Colors.white70 : Colors.black54,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.poppins(
              color: isDarkTheme ? Colors.white : Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}