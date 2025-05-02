import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:energenius/database/database_helper.dart';
import 'package:provider/provider.dart';
import '../theme_provider.dart';
import '../utils/conversion_utilities.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../localization/app_localizations.dart';
import '../localization/language_provider.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _userDevices = [];
  String _energyUnit = 'kWh';
  String _currentLanguage = '';

  @override
  void initState() {
    super.initState();
    _fetchData();
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

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _energyUnit = prefs.getString('energyUnit') ?? 'kWh';
      });
    }
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      _categories = await DatabaseHelper.instance.getCategories();
      debugPrint('Fetched categories: $_categories');

      final userId = FirebaseAuth.instance.currentUser!.uid;
      _userDevices = await DatabaseHelper.instance.getDevices(userId);
      debugPrint('Fetched user devices: $_userDevices');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching data: $e', style: const TextStyle(color: Colors.white)),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
    
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showAddDevicePopup() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AddDeviceDialog(
        categories: _categories,
        onSave: () => _fetchData(), // Refresh the device list after saving
      ),
    );
  }

  void _showCustomDevicePopup() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => CustomDeviceDialog(
        categories: _categories,
        onSave: () => _fetchData(),
      ),
    );
  }

  void _showEditDevicePopup(Map<String, dynamic> device) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => EditDeviceDialog(
        categories: _categories,
        device: device,
        onSave: () => _fetchData(),
      ),
    );
  }

  // New method to delete a device
  Future<void> _deleteDevice(String deviceId) async {
    try {
      await FirebaseFirestore.instance.collection('devices').doc(deviceId).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green, 
          content: Text('device_deleted'.tr(context), style: const TextStyle(color: Colors.white)),
          duration: const Duration(seconds: 1),
        ),
      );
      _fetchData(); // Refresh the device list after deletion
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent, 
          content: Text('Error deleting device: $e', style: const TextStyle(color: Colors.white)),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  IconData _getCategoryIcon(String? categoryId) {
    final category = _categories.firstWhere(
          (cat) => cat['id'] == categoryId,
      orElse: () => {'name': 'Unknown'},
    );
    switch (category['name'] as String) {
      case 'Air Conditioner':
        return Icons.ac_unit;
      case 'TV':
        return Icons.tv;
      case 'Refrigerator':
        return Icons.kitchen;
      case 'Washing Machine':
        return Icons.local_laundry_service;
      case 'Microwave':
        return Icons.microwave; // Updated icon for Microwave
      case 'Electric Oven':
        return Icons.local_dining;
      case 'Water Heater':
        return Icons.hot_tub;
      case 'Lighting':
        return Icons.lightbulb;
      case 'Computer':
        return Icons.computer;
      case 'Vacuum Cleaner':
        return Icons.cleaning_services;
      default:
        return Icons.device_unknown;
    }
  }

  String categoryName(String? categoryId) {
    final category = _categories.firstWhere(
          (cat) => cat['id'] == categoryId,
      orElse: () => {'name': 'Unknown'},
    );
    return category['name'] as String? ?? 'Unknown';
  }

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

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool isDarkTheme = themeProvider.isDarkTheme;
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: _isLoading
          ? Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDarkTheme
                      ? [Color.fromRGBO(68, 138, 255, 0.2), Colors.black]
                      : [Colors.white, Colors.grey[300]!],
                ),
              ),
              child: Center(
                child: CircularProgressIndicator(
                  color: Colors.blueAccent,
                ),
              ),
            )
          : _buildDeviceList(isDarkTheme),
    );
  }

  Widget _buildDeviceList(bool isDarkTheme) {
    return Container(
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
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'devices'.tr(context),
                    style: GoogleFonts.poppins(
                      color: isDarkTheme ? Colors.white : Colors.black,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: _showAddDevicePopup,
                        style: ElevatedButton.styleFrom(
                          shape: const CircleBorder(),
                          backgroundColor: Colors.blueAccent,
                          padding: const EdgeInsets.all(12),
                          elevation: 4,
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _showCustomDevicePopup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text('custom'.tr(context), style: GoogleFonts.poppins(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _userDevices.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.devices,
                              size: 100,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              "no_devices_added".tr(context),
                              style: GoogleFonts.poppins(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "tap_to_add_device".tr(context),
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: Colors.white70,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _userDevices.length,
                        itemBuilder: (context, index) {
                          final device = _userDevices[index];
                          final power = device['power_consumption'] as double? ?? 0.0;
                          final usage = device['usage_hours_per_day'] as double? ?? 0.0;
                          final dailyConsumption = power * usage;
                          final deviceId = device['id'] as String? ?? ''; // Handle potential null
                          return Card(
                            color: isDarkTheme 
                                ? Colors.white.withAlpha(26) 
                                : Colors.grey[200],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            elevation: 5,
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withAlpha(isDarkTheme ? 40 : 20),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _getCategoryIcon(device['category_id']),
                                    color: Colors.blueAccent,
                                    size: 30,
                                  ),
                                ),
                                title: Text(
                                  '${device['manufacturer'] ?? 'Unknown'} ${device['model'] ?? ''}',
                                  style: GoogleFonts.poppins(
                                    color: isDarkTheme ? Colors.white : Colors.black87,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text('Category: ${categoryName(device['category_id'])}',
                                        style: GoogleFonts.poppins(color: isDarkTheme ? Colors.blue[300] : Colors.blue[700], fontSize: 13)),
                                    Text('power_consumption'.tr(context) + ': ${power.toStringAsFixed(2)} kW',
                                        style: GoogleFonts.poppins(color: isDarkTheme ? Colors.blue[300] : Colors.blue[700], fontSize: 13)),
                                    Text('usage_hours'.tr(context) + ': ${usage.toStringAsFixed(1)} hrs/day',
                                        style: GoogleFonts.poppins(color: isDarkTheme ? Colors.blue[300] : Colors.blue[700], fontSize: 13)),
                                    Text('daily_consumption'.tr(context) + ': ${_formatEnergyValue(dailyConsumption)}',
                                        style: GoogleFonts.poppins(color: isDarkTheme ? Colors.blue[300] : Colors.blue[700], fontSize: 13)),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit,
                                        color: Colors.blueAccent,
                                      ),
                                      tooltip: 'Edit device',
                                      onPressed: () => _showEditDevicePopup(device),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.redAccent,
                                      ),
                                      tooltip: 'Delete device',
                                      onPressed: () {
                                        // Show confirmation dialog before deletion
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            backgroundColor: isDarkTheme ? Colors.grey[900] : Colors.white,
                                            title: Text(
                                              'delete_device_title'.tr(context),
                                              style: GoogleFonts.poppins(
                                                  color: isDarkTheme ? Colors.white : Colors.black, 
                                                  fontSize: 20, 
                                                  fontWeight: FontWeight.bold),
                                            ),
                                            content: Text(
                                              'delete_device_confirmation'.tr(context),
                                              style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black87),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(context).pop(),
                                                child: Text('cancel'.tr(context),
                                                    style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54)),
                                              ),
                                              ElevatedButton(
                                                onPressed: () {
                                                  Navigator.of(context).pop(); // Close dialog
                                                  if (deviceId.isNotEmpty) {
                                                    _deleteDevice(deviceId); // Delete the device
                                                  } else {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        backgroundColor: Colors.red,
                                                        content: Text('error_device_id'.tr(context), style: const TextStyle(color: Colors.white)),
                                                      ),
                                                    );
                                                  }
                                                },
                                                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                                child: Text('delete'.tr(context),
                                                    style: GoogleFonts.poppins(color: Colors.white)),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Dialog for adding a preset device
class AddDeviceDialog extends StatefulWidget {
  final List<Map<String, dynamic>> categories;
  final VoidCallback onSave;

  const AddDeviceDialog({super.key, required this.categories, required this.onSave});

  @override
  State<AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<AddDeviceDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedCategory;
  String? _selectedManufacturer;
  String? _selectedModel;
  double? _powerConsumption;
  double? _usageHoursPerDay;
  final TextEditingController _usageHoursController = TextEditingController();
  List<Map<String, dynamic>> _manufacturers = [];
  List<Map<String, dynamic>> _models = [];
  List<Map<String, dynamic>> _allDevices = [];

  @override
  void initState() {
    super.initState();
    _fetchPresetDevices();
  }

  Future<void> _fetchPresetDevices() async {
    _allDevices = await DatabaseHelper.instance.getPresetDevices();
    debugPrint('Fetched preset devices in dialog: $_allDevices');
  }

  void _updateManufacturers(String? categoryId) {
    setState(() {
      _selectedManufacturer = null;
      _selectedModel = null;
      _powerConsumption = null;
      _models = [];
      _manufacturers = [];

      if (categoryId == null) {
        debugPrint('Category ID is null');
        return;
      }

      final filteredDevices = _allDevices.where((device) => device['category_id'] == categoryId).toList();
      debugPrint('Filtered devices for category $categoryId: $filteredDevices');

      final uniqueManufacturers = filteredDevices.map((device) => device['manufacturer'] as String).toSet().toList();

      _manufacturers = uniqueManufacturers.map((manufacturer) => {'name': manufacturer}).toList();
      debugPrint('Updated manufacturers: $_manufacturers');

      if (_manufacturers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No manufacturers found for this category.', style: const TextStyle(color: Colors.white)),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    });
  }

  void _updateModels(String? categoryId, String? manufacturer) {
    setState(() {
      _selectedModel = null;
      _powerConsumption = null;
      _models = [];

      if (categoryId == null || manufacturer == null) {
        debugPrint('Category ID or manufacturer is null');
        return;
      }

      final filteredDevices = _allDevices
          .where((device) => device['category_id'] == categoryId && device['manufacturer'] == manufacturer)
          .toList();

      _models = filteredDevices.map((device) {
        return {
          'name': device['model'],
          'power_consumption': device['power_consumption'],
        };
      }).toList();
      debugPrint('Updated models: $_models');
    });
  }

  void _updatePowerConsumption(String? model) {
    setState(() {
      if (model == null) {
        _powerConsumption = null;
        return;
      }

      final selectedDevice = _models.firstWhere(
            (device) => device['name'] == model,
        orElse: () => {'power_consumption': null},
      );
      _powerConsumption = selectedDevice['power_consumption'] as double?;
    });
  }

  Future<void> _saveDevice() async {
    if (_formKey.currentState!.validate()) {
      try {
        final userId = FirebaseAuth.instance.currentUser!.uid;
        await FirebaseFirestore.instance.collection('devices').add({
          'category_id': _selectedCategory,
          'manufacturer': _selectedManufacturer,
          'model': _selectedModel,
          'power_consumption': _powerConsumption,
          'usage_hours_per_day': _usageHoursPerDay,
          'is_user_added': 1,
          'user_id': userId,
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green, 
            content: Text('device_added'.tr(context), style: const TextStyle(color: Colors.white)),
            duration: const Duration(seconds: 1),
          ),
        );
        Navigator.of(context).pop();
        widget.onSave();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red, 
            content: Text('error_save_device'.tr(context) + ': $e', style: const TextStyle(color: Colors.white)),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool isDarkTheme = themeProvider.isDarkTheme;
    
    return AlertDialog(
      backgroundColor: isDarkTheme ? Colors.grey[900] : Colors.white,
      title: Text('add_device'.tr(context),
          style: GoogleFonts.poppins(
            color: isDarkTheme ? Colors.white : Colors.black, 
            fontSize: 20, 
            fontWeight: FontWeight.bold
          )),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                hint: Text("select_category".tr(context), style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54)),
                items: widget.categories.map((category) {
                  return DropdownMenuItem<String>(
                    value: category['id'] as String,
                    child: Text(category['name'] as String, style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white : Colors.black)),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCategory = value;
                    _updateManufacturers(value);
                  });
                },
                validator: (value) => value == null ? "category".tr(context) : null,
                decoration: InputDecoration(
                  labelText: "category".tr(context),
                  labelStyle: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: isDarkTheme ? Colors.white70 : Colors.black38),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent),
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                ),
                dropdownColor: isDarkTheme ? Colors.grey[800] : Colors.grey[100],
                style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white : Colors.black),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedManufacturer,
                hint: Text('select_manufacturer'.tr(context), style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54)),
                items: _manufacturers.map((manufacturer) {
                  return DropdownMenuItem<String>(
                    value: manufacturer['name'] as String,
                    child: Text(manufacturer['name'] as String, style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white : Colors.black)),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedManufacturer = value;
                    _updateModels(_selectedCategory, value);
                  });
                },
                validator: (value) => value == null ? 'Please select a manufacturer' : null,
                decoration: InputDecoration(
                  labelText: 'Manufacturer',
                  labelStyle: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: isDarkTheme ? Colors.white70 : Colors.black38),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent),
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                ),
                dropdownColor: isDarkTheme ? Colors.grey[800] : Colors.grey[100],
                style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white : Colors.black),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedModel,
                hint: Text('select_model'.tr(context), style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54)),
                items: _models.map((model) {
                  return DropdownMenuItem<String>(
                    value: model['name'] as String,
                    child: Text(model['name'] as String, style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white : Colors.black)),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedModel = value;
                    _updatePowerConsumption(value);
                  });
                },
                validator: (value) => value == null ? 'Please select a model' : null,
                decoration: InputDecoration(
                  labelText: 'Model',
                  labelStyle: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: isDarkTheme ? Colors.white70 : Colors.black38),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent),
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                ),
                dropdownColor: isDarkTheme ? Colors.grey[800] : Colors.grey[100],
                style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white : Colors.black),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usageHoursController,
                keyboardType: TextInputType.number,
                style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  labelText: 'Usage Hours per Day',
                  labelStyle: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: isDarkTheme ? Colors.white70 : Colors.black38),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent),
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                ),
                onChanged: (value) {
                  setState(() {
                    _usageHoursPerDay = double.tryParse(value) ?? 0.0;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter usage hours';
                  }
                  final hours = double.tryParse(value);
                  if (hours == null || hours <= 0) {
                    return 'Usage hours must be a positive number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Power Consumption: ${_powerConsumption?.toStringAsFixed(2) ?? 'N/A'} kW',
                style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white : Colors.black, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('cancel'.tr(context), style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54)),
        ),
        ElevatedButton(
          onPressed: _saveDevice,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
          child: Text('add_device_button'.tr(context), style: GoogleFonts.poppins(color: Colors.white)),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _usageHoursController.dispose();
    super.dispose();
  }
}

// Dialog for adding a custom device
class CustomDeviceDialog extends StatefulWidget {
  final List<Map<String, dynamic>> categories;
  final VoidCallback onSave;

  const CustomDeviceDialog({super.key, required this.categories, required this.onSave});

  @override
  State<CustomDeviceDialog> createState() => _CustomDeviceDialogState();
}

class _CustomDeviceDialogState extends State<CustomDeviceDialog> {
  final _customFormKey = GlobalKey<FormState>();
  String? _customCategory;
  String? _customManufacturer;
  String? _customModel;
  double? _customPowerConsumption;
  double? _customUsageHours;
  final _customUsageHoursController = TextEditingController();
  final _customPowerController = TextEditingController();

  Future<void> _saveCustomDevice() async {
    if (_customFormKey.currentState!.validate()) {
      try {
        final userId = FirebaseAuth.instance.currentUser!.uid;
        await FirebaseFirestore.instance.collection('devices').add({
          'category_id': _customCategory,
          'manufacturer': _customManufacturer,
          'model': _customModel,
          'power_consumption': _customPowerConsumption,
          'usage_hours_per_day': _customUsageHours,
          'is_user_added': 1,
          'user_id': userId,
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green, 
            content: Text('custom_device_added'.tr(context), style: const TextStyle(color: Colors.white)),
            duration: const Duration(seconds: 1),
          ),
        );
        Navigator.of(context).pop();
        widget.onSave();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red, 
            content: Text('error_save_custom'.tr(context) + ': $e', style: const TextStyle(color: Colors.white)),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool isDarkTheme = themeProvider.isDarkTheme;
    
    return AlertDialog(
      backgroundColor: isDarkTheme ? Colors.grey[900] : Colors.white,
      title: Text('add_custom_device'.tr(context),
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          )),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _customFormKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: _customCategory,
                hint: Text('Select Category', style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54)),
                items: widget.categories.map((category) {
                  return DropdownMenuItem<String>(
                    value: category['id'] as String,
                    child: Text(category['name'] as String, style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white : Colors.black)),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _customCategory = value),
                validator: (value) => value == null ? 'Please select a category' : null,
                decoration: InputDecoration(
                  labelText: 'Category',
                  labelStyle: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: isDarkTheme ? Colors.white70 : Colors.black38),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent),
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                ),
                dropdownColor: isDarkTheme ? Colors.grey[800] : Colors.grey[100],
                style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white : Colors.black),
              ),
              const SizedBox(height: 16),
              TextFormField(
                style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  labelText: 'Manufacturer',
                  labelStyle: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: isDarkTheme ? Colors.white70 : Colors.black38),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent),
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                ),
                validator: (value) => value == null || value.isEmpty ? 'Enter manufacturer' : null,
                onChanged: (value) => _customManufacturer = value,
              ),
              const SizedBox(height: 16),
              TextFormField(
                style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  labelText: 'Model',
                  labelStyle: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: isDarkTheme ? Colors.white70 : Colors.black38),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent),
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                ),
                validator: (value) => value == null || value.isEmpty ? 'Enter model' : null,
                onChanged: (value) => _customModel = value,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _customPowerController,
                keyboardType: TextInputType.number,
                style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  labelText: 'Power Consumption (kW)',
                  labelStyle: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: isDarkTheme ? Colors.white70 : Colors.black38),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent),
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter power consumption';
                  }
                  final power = double.tryParse(value);
                  if (power == null || power <= 0) {
                    return 'Power must be a positive number';
                  }
                  return null;
                },
                onChanged: (value) {
                  _customPowerConsumption = double.tryParse(value) ?? 0.0;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _customUsageHoursController,
                keyboardType: TextInputType.number,
                style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  labelText: 'Usage Hours per Day',
                  labelStyle: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: isDarkTheme ? Colors.white70 : Colors.black38),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent),
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter usage hours';
                  }
                  final hours = double.tryParse(value);
                  if (hours == null || hours <= 0) {
                    return 'Usage hours must be a positive number';
                  }
                  return null;
                },
                onChanged: (value) {
                  _customUsageHours = double.tryParse(value) ?? 0.0;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('cancel'.tr(context), style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54)),
        ),
        ElevatedButton(
          onPressed: _saveCustomDevice,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
          child: Text('add_custom_device'.tr(context), style: GoogleFonts.poppins(color: Colors.white)),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _customUsageHoursController.dispose();
    _customPowerController.dispose();
    super.dispose();
  }
}

class EditDeviceDialog extends StatefulWidget {
  final List<Map<String, dynamic>> categories;
  final Map<String, dynamic> device;
  final VoidCallback onSave;

  const EditDeviceDialog({
    super.key, 
    required this.categories, 
    required this.device, 
    required this.onSave
  });

  @override
  State<EditDeviceDialog> createState() => _EditDeviceDialogState();
}

class _EditDeviceDialogState extends State<EditDeviceDialog> {
  final _formKey = GlobalKey<FormState>();
  late String? _selectedCategory;
  late String? _manufacturer;
  late String? _model;
  late double? _powerConsumption;
  late double? _usageHoursPerDay;
  late TextEditingController _usageHoursController;
  late TextEditingController _powerConsumptionController;
  late TextEditingController _manufacturerController;
  late TextEditingController _modelController;

  @override
  void initState() {
    super.initState();
    
    // Initialize with existing device data
    _selectedCategory = widget.device['category_id'] as String?;
    _manufacturer = widget.device['manufacturer'] as String?;
    _model = widget.device['model'] as String?;
    _powerConsumption = widget.device['power_consumption'] as double?;
    _usageHoursPerDay = widget.device['usage_hours_per_day'] as double?;
    
    // Initialize controllers with existing values
    _usageHoursController = TextEditingController(
      text: _usageHoursPerDay?.toString() ?? ''
    );
    _powerConsumptionController = TextEditingController(
      text: _powerConsumption?.toString() ?? ''
    );
    _manufacturerController = TextEditingController(text: _manufacturer ?? '');
    _modelController = TextEditingController(text: _model ?? '');
  }

  Future<void> _updateDevice() async {
    if (_formKey.currentState!.validate()) {
      try {
        final deviceId = widget.device['id'] as String? ?? '';
        if (deviceId.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red,
              content: Text('error_device_id'.tr(context), style: const TextStyle(color: Colors.white)),
            ),
          );
          return;
        }
        
        await FirebaseFirestore.instance.collection('devices').doc(deviceId).update({
          'category_id': _selectedCategory,
          'manufacturer': _manufacturer,
          'model': _model,
          'power_consumption': _powerConsumption,
          'usage_hours_per_day': _usageHoursPerDay,
        });
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text('device_updated'.tr(context), style: const TextStyle(color: Colors.white)),
            duration: const Duration(seconds: 1),
          )
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        widget.onSave();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('error_update_device'.tr(context) + ': $e', style: const TextStyle(color: Colors.white)),
            duration: const Duration(seconds: 1),
          )
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool isDarkTheme = themeProvider.isDarkTheme;
    
    return AlertDialog(
      backgroundColor: isDarkTheme ? Colors.grey[900] : Colors.white,
      title: Text(
        'update_device'.tr(context),
        style: GoogleFonts.poppins(
          color: isDarkTheme ? Colors.white : Colors.black, 
          fontSize: 20, 
          fontWeight: FontWeight.bold
        )
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                hint: Text('Select Category', style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54)),
                items: widget.categories.map((category) {
                  return DropdownMenuItem<String>(
                    value: category['id'] as String,
                    child: Text(category['name'] as String, style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white : Colors.black)),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCategory = value;
                  });
                },
                validator: (value) => value == null ? 'Please select a category' : null,
                decoration: InputDecoration(
                  labelText: 'Category',
                  labelStyle: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: isDarkTheme ? Colors.white70 : Colors.black38),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent),
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                ),
                dropdownColor: isDarkTheme ? Colors.grey[800] : Colors.grey[100],
                style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white : Colors.black),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _manufacturerController,
                style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  labelText: 'Manufacturer',
                  labelStyle: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: isDarkTheme ? Colors.white70 : Colors.black38),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent),
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                ),
                validator: (value) => value == null || value.isEmpty ? 'Please enter manufacturer' : null,
                onChanged: (value) => _manufacturer = value,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _modelController,
                style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  labelText: 'Model',
                  labelStyle: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: isDarkTheme ? Colors.white70 : Colors.black38),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent),
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                ),
                validator: (value) => value == null || value.isEmpty ? 'Please enter model' : null,
                onChanged: (value) => _model = value,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _powerConsumptionController,
                keyboardType: TextInputType.number,
                style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  labelText: 'Power Consumption (kW)',
                  labelStyle: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: isDarkTheme ? Colors.white70 : Colors.black38),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent),
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter power consumption';
                  }
                  final power = double.tryParse(value);
                  if (power == null || power <= 0) {
                    return 'Power must be a positive number';
                  }
                  return null;
                },
                onChanged: (value) {
                  _powerConsumption = double.tryParse(value) ?? 0.0;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usageHoursController,
                keyboardType: TextInputType.number,
                style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  labelText: 'Usage Hours per Day',
                  labelStyle: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: isDarkTheme ? Colors.white70 : Colors.black38),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent),
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter usage hours';
                  }
                  final hours = double.tryParse(value);
                  if (hours == null || hours <= 0) {
                    return 'Usage hours must be a positive number';
                  }
                  return null;
                },
                onChanged: (value) {
                  _usageHoursPerDay = double.tryParse(value) ?? 0.0;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('cancel'.tr(context), style: GoogleFonts.poppins(color: isDarkTheme ? Colors.white70 : Colors.black54)),
        ),
        ElevatedButton(
          onPressed: _updateDevice,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
          child: Text('update_device_button'.tr(context), style: GoogleFonts.poppins(color: Colors.white)),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _usageHoursController.dispose();
    _powerConsumptionController.dispose();
    _manufacturerController.dispose();
    _modelController.dispose();
    super.dispose();
  }
}