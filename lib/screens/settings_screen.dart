import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../theme_provider.dart';
import '../utils/conversion_utilities.dart';
import '../localization/language_provider.dart';
import '../localization/app_localizations.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _realTimeSync = true;
  String _energyUnit = 'kWh';
  String _currency = 'EGP';
  bool _notificationsEnabled = true;
  String _exportFrequency = 'weekly';
  String _language = 'en';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      
      final languageCode = prefs.getString(AppLocalizations.LANGUAGE_CODE) ?? 'en';
      
      setState(() {
        _realTimeSync = prefs.getBool('realTimeSync') ?? true;
        _energyUnit = prefs.getString('energyUnit') ?? 'kWh';
        _currency = prefs.getString('currency') ?? 'EGP';
        _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
        _exportFrequency = prefs.getString('exportFrequency') ?? 'weekly';
        _language = languageCode;
      });
      
      // Ensure the LanguageProvider is in sync with the loaded language
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      if (languageProvider.locale.languageCode != languageCode) {
        languageProvider.changeLanguage(languageCode);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("error_loading_settings".tr(context) + ": $e", style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 1),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('realTimeSync', _realTimeSync);
      await prefs.setString('energyUnit', _energyUnit);
      await prefs.setString('currency', _currency);
      await prefs.setBool('notificationsEnabled', _notificationsEnabled);
      await prefs.setString('exportFrequency', _exportFrequency);
      
      // Save language through AppLocalizations to ensure consistency
      await AppLocalizations.setLocale(_language);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("settings_saved".tr(context), style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.blueAccent,
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("error_saving_settings".tr(context) + ": $e", style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoginScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("error_logging_out".tr(context) + ": $e", style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _deleteAccount() async {
    try {
      // Firebase requires recent authentication for sensitive operations
      // Show a reauthentication dialog first
      final user = FirebaseAuth.instance.currentUser!;
      final TextEditingController passwordController = TextEditingController();
      bool reAuthSuccess = false;
      
      // Show authentication dialog
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey[900] : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text(
            "authentication_required".tr(context) ?? "Authentication Required",
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "enter_password_to_continue".tr(context) ?? "Please enter your password to continue with account deletion.",
                style: GoogleFonts.poppins(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: "password".tr(context) ?? "Password",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                "cancel".tr(context) ?? "Cancel",
                style: GoogleFonts.poppins(color: Colors.blueAccent),
              ),
            ),
            TextButton(
              onPressed: () async {
                try {
                  // Create credentials
                  AuthCredential credential = EmailAuthProvider.credential(
                    email: user.email!,
                    password: passwordController.text,
                  );
                  
                  // Reauthenticate user
                  await user.reauthenticateWithCredential(credential);
                  reAuthSuccess = true;
                  Navigator.pop(context);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "authentication_failed".tr(context) ?? "Authentication failed. Please try again.",
                        style: const TextStyle(color: Colors.white)
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: Text(
                "authenticate".tr(context) ?? "Authenticate",
                style: GoogleFonts.poppins(color: Colors.redAccent),
              ),
            ),
          ],
        ),
      );
      
      // If user canceled or authentication failed, return
      if (!reAuthSuccess) return;
      
      // Now proceed with account deletion
      String userId = user.uid;
      await FirebaseFirestore.instance.collection('users').doc(userId).delete();
      await user.delete();
      await _clearCache();
      
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoginScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("error_deleting_account".tr(context) + ": $e", style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("cache_cleared".tr(context), style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.blueAccent,
          duration: const Duration(seconds: 1),
        ),
      );
      _loadSettings(); // Reload default settings
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("error_clearing_cache".tr(context) + ": $e", style: const TextStyle(color: Colors.white)),
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "settings".tr(context),
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isDarkTheme ? Colors.white : Colors.black,
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDarkTheme
                ? [Colors.blueAccent.withAlpha(77), Colors.black]
                : [Colors.white, Colors.grey[300]!],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
            : SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Theme Settings
                Text(
                  "theme".tr(context),
                  style: GoogleFonts.poppins(
                    color: isDarkTheme ? Colors.white : Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SwitchListTile(
                  title: Text(
                    "dark_theme".tr(context),
                    style: GoogleFonts.poppins(
                      color: isDarkTheme ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  value: isDarkTheme,
                  onChanged: (value) {
                    themeProvider.toggleTheme(value);
                    _saveSettings();
                  },
                  activeColor: Colors.blueAccent,
                ),
                const SizedBox(height: 20),

                // Data Sync Settings
                Text(
                  "data_sync".tr(context),
                  style: GoogleFonts.poppins(
                    color: isDarkTheme ? Colors.white : Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SwitchListTile(
                  title: Text(
                    "real_time_sync".tr(context),
                    style: GoogleFonts.poppins(
                      color: isDarkTheme ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    "real_time_sync_description".tr(context),
                    style: GoogleFonts.poppins(
                      color: isDarkTheme ? Colors.white54 : Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                  value: _realTimeSync,
                  onChanged: (value) {
                    setState(() {
                      _realTimeSync = value;
                      _saveSettings();
                    });
                  },
                  activeColor: Colors.blueAccent,
                ),
                const SizedBox(height: 20),

                // Energy Unit Settings
                Text(
                  "energy_unit_title".tr(context),
                  style: GoogleFonts.poppins(
                    color: isDarkTheme ? Colors.white : Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Card(
                  color: isDarkTheme ? Colors.white.withAlpha(26) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "select_energy_unit_text".tr(context),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white70 : Colors.black87,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: _energyUnit,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: isDarkTheme ? Colors.white.withAlpha(26) : Colors.grey[200],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          dropdownColor: isDarkTheme ? Colors.grey[900] : Colors.white,
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
                            setState(() {
                              _energyUnit = newValue!;
                              _saveSettings();
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("energy_unit_updated".trParams(context, [_energyUnit]), style: const TextStyle(color: Colors.white)),
                                backgroundColor: Colors.blueAccent,
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "energy_unit_apply_note".tr(context),
                          style: GoogleFonts.poppins(
                            color: Colors.blueAccent,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),

                // Currency Settings
                Text(
                  "currency_title".tr(context),
                  style: GoogleFonts.poppins(
                    color: isDarkTheme ? Colors.white : Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Card(
                  color: isDarkTheme ? Colors.white.withAlpha(26) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "select_currency_text".tr(context),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white70 : Colors.black87,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: _currency,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: isDarkTheme ? Colors.white.withAlpha(26) : Colors.grey[200],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          dropdownColor: isDarkTheme ? Colors.grey[900] : Colors.white,
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
                            setState(() {
                              _currency = newValue!;
                              _saveSettings();
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("currency_updated".trParams(context, [_currency]), style: const TextStyle(color: Colors.white)),
                                backgroundColor: Colors.blueAccent,
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "currency_apply_note".tr(context),
                          style: GoogleFonts.poppins(
                            color: Colors.blueAccent,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),

                // Notification Settings
                Text(
                  "notifications_title".tr(context),
                  style: GoogleFonts.poppins(
                    color: isDarkTheme ? Colors.white : Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SwitchListTile(
                  title: Text(
                    "enable_notifications".tr(context),
                    style: GoogleFonts.poppins(
                      color: isDarkTheme ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    "notifications_description".tr(context),
                    style: GoogleFonts.poppins(
                      color: isDarkTheme ? Colors.white54 : Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                  value: _notificationsEnabled,
                  onChanged: (value) {
                    setState(() {
                      _notificationsEnabled = value;
                      _saveSettings();
                    });
                  },
                  activeColor: Colors.blueAccent,
                ),
                const SizedBox(height: 20),

                // Data Export Frequency
                Text(
                  "data_export".tr(context),
                  style: GoogleFonts.poppins(
                    color: isDarkTheme ? Colors.white : Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                DropdownButtonFormField<String>(
                  value: _exportFrequency,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: isDarkTheme ? Colors.white.withAlpha(26) : Colors.grey[200],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  dropdownColor: isDarkTheme ? Colors.grey[900] : Colors.white,
                  style: GoogleFonts.poppins(
                    color: isDarkTheme ? Colors.white : Colors.black,
                  ),
                  items: <String>['daily', 'weekly', 'monthly']
                      .map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _exportFrequency = newValue!;
                      _saveSettings();
                    });
                  },
                ),
                const SizedBox(height: 20),

                // Language Selection
                Text(
                  "language".tr(context),
                  style: GoogleFonts.poppins(
                    color: isDarkTheme ? Colors.white : Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                DropdownButtonFormField<String>(
                  value: _language,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: isDarkTheme ? Colors.white.withAlpha(26) : Colors.grey[200],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  dropdownColor: isDarkTheme ? Colors.grey[900] : Colors.white,
                  style: GoogleFonts.poppins(
                    color: isDarkTheme ? Colors.white : Colors.black,
                  ),
                  items: <Map<String, String>>[
                    {'code': 'en', 'name': 'English'},
                    {'code': 'ar', 'name': 'العربية'},
                    {'code': 'fr', 'name': 'Français'},
                  ].map<DropdownMenuItem<String>>((Map<String, String> language) {
                    return DropdownMenuItem<String>(
                      value: language['code'],
                      child: Text(language['name']!),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _language = newValue;
                        _saveSettings();
                      });
                      // Update app language using the LanguageProvider
                      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
                      languageProvider.changeLanguage(newValue);
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("language_updated".tr(context), style: const TextStyle(color: Colors.white)),
                          backgroundColor: Colors.blueAccent,
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 20),

                // Account Management
                Text(
                  "profile".tr(context),
                  style: GoogleFonts.poppins(
                    color: isDarkTheme ? Colors.white : Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  title: Text(
                    "view_profile".tr(context),
                    style: GoogleFonts.poppins(
                      color: Colors.blueAccent,
                    ),
                  ),
                  trailing: const Icon(Icons.person, color: Colors.blueAccent),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => ProfileScreen()),
                    );
                  },
                ),
                const SizedBox(height: 10),
                ListTile(
                  title: Text(
                    "logout_title".tr(context),
                    style: GoogleFonts.poppins(
                      color: Colors.redAccent,
                    ),
                  ),
                  trailing: const Icon(Icons.logout, color: Colors.redAccent),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: isDarkTheme ? Colors.grey[900] : Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        title: Text(
                          "logout_title".tr(context),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        content: Text(
                          "logout_confirmation".tr(context),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              "cancel".tr(context),
                              style: GoogleFonts.poppins(color: Colors.blueAccent),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _logout();
                            },
                            child: Text(
                              "logout".tr(context),
                              style: GoogleFonts.poppins(color: Colors.redAccent),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                ListTile(
                  title: Text(
                    "delete_account_title".tr(context),
                    style: GoogleFonts.poppins(
                      color: Colors.redAccent,
                    ),
                  ),
                  trailing: const Icon(Icons.delete, color: Colors.redAccent),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: isDarkTheme ? Colors.grey[900] : Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        title: Text(
                          "delete_account_title".tr(context),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        content: Text(
                          "delete_account_confirmation".tr(context),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              "cancel".tr(context),
                              style: GoogleFonts.poppins(color: Colors.blueAccent),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _deleteAccount();
                            },
                            child: Text(
                              "delete".tr(context),
                              style: GoogleFonts.poppins(color: Colors.redAccent),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),

                // Clear Cache/Data
                Text(
                  "maintenance".tr(context),
                  style: GoogleFonts.poppins(
                    color: isDarkTheme ? Colors.white : Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ListTile(
                  title: Text(
                    "clear_cache".tr(context),
                    style: GoogleFonts.poppins(
                      color: isDarkTheme ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  trailing: const Icon(Icons.delete_sweep, color: Colors.blueAccent),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: isDarkTheme ? Colors.grey[900] : Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        title: Text(
                          "clear_cache_title".tr(context),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        content: Text(
                          "clear_cache_confirmation".tr(context),
                          style: GoogleFonts.poppins(
                            color: isDarkTheme ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              "cancel".tr(context),
                              style: GoogleFonts.poppins(color: Colors.blueAccent),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _clearCache();
                            },
                            child: Text(
                              "clear".tr(context),
                              style: GoogleFonts.poppins(color: Colors.blueAccent),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                // Add bottom padding for navigation bar
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }
}