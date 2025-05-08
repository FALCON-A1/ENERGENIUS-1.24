import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:async';
import 'firebase_options.dart'; // Ensure this file exists
import 'theme_provider.dart';
import 'screens/main_screen.dart';
import 'screens/login_screen.dart';
import 'dart:developer' as developer;
import 'localization/app_localizations.dart';
import 'localization/language_provider.dart';
import 'database/database_helper.dart';
import 'services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform, // Use generated options
    );
    developer.log("Firebase initialized successfully");
    
    // Pre-load the saved language preference
    await AppLocalizations.getLocale();
    
    // Initialize database for current user if logged in
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      await DatabaseHelper.instance.initialize(currentUser.uid);
      developer.log("Database initialized for user: ${currentUser.uid}");
      
      // Start the timer to periodically send consumption data
      _startConsumptionDataTimer(currentUser.uid);
    }
    
    // Initialize the background service
    await BackgroundService().initializeService();
    developer.log("Background service initialized");
    
    // Set up auth state listener to handle database operations on auth changes
    _setupAuthListener();
    
  } catch (e) {
    developer.log("Error initializing Firebase: $e");
  }
  runApp(const MyApp());
}

// Timer to periodically send consumption data to the database
Timer? _consumptionDataTimer;
// Timer to reset device uptime at midnight
Timer? _midnightResetTimer;

void _startConsumptionDataTimer(String userId) {
  // Cancel any existing timer
  _consumptionDataTimer?.cancel();
  
  // Create a new timer that runs every 5 minutes (reduced from 10 minutes)
  _consumptionDataTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
    _sendConsumptionData(userId);
  });
  
  // Also send data immediately on app start
  _sendConsumptionData(userId);
  
  developer.log("Started consumption data timer for user: $userId");
  
  // Start the midnight reset timer
  _setupMidnightResetTimer(userId);
}

void _setupMidnightResetTimer(String userId) {
  // Cancel any existing timer
  _midnightResetTimer?.cancel();
  
  // Calculate time until next midnight
  final now = DateTime.now();
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final timeUntilMidnight = tomorrow.difference(now);
  
  // Set a one-time timer to trigger at midnight
  _midnightResetTimer = Timer(timeUntilMidnight, () {
    // Reset daily usage
    DatabaseHelper.instance.checkAndResetDailyUsage(userId).then((_) {
      developer.log("Midnight reset performed for user: $userId");
      // Set up the next day's timer
      _setupMidnightResetTimer(userId);
    });
  });
  
  developer.log("Midnight reset timer set for ${timeUntilMidnight.inHours} hours and ${timeUntilMidnight.inMinutes % 60} minutes from now");
}

Future<void> _sendConsumptionData(String userId) async {
  try {
    // First check and reset daily usage if needed
    await DatabaseHelper.instance.checkAndResetDailyUsage(userId);
    
    // Get all user devices to check for active devices
    List<Map<String, dynamic>> devices = await DatabaseHelper.instance.getUserDevices(userId);
    
    // For each active device, update its uptime
    for (var device in devices) {
      String deviceId = device['id'];
      bool isActive = device['last_active'] != null;
      
      if (isActive) {
        // Update uptime for active devices
        await DatabaseHelper.instance.updateDeviceUptime(
          deviceId: deviceId,
          isActive: true,
        );
        developer.log("Updated uptime for active device: ${device['model']}");
      }
    }
    
    // Then send consumption data
    await DatabaseHelper.instance.autoSendConsumptionData(userId);
  } catch (e) {
    developer.log("Error in periodic consumption data send: $e");
  }
}

void _setupAuthListener() {
  FirebaseAuth.instance.authStateChanges().listen((User? user) {
    if (user != null) {
      // User signed in
      DatabaseHelper.instance.initialize(user.uid);
      _startConsumptionDataTimer(user.uid);
      developer.log("Auth state changed: User signed in - ${user.uid}");
    } else {
      // User signed out
      _consumptionDataTimer?.cancel();
      _consumptionDataTimer = null;
      _midnightResetTimer?.cancel();
      _midnightResetTimer = null;
      developer.log("Auth state changed: User signed out");
    }
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App resumed from background, refresh data
      _refreshAppDataOnResume();
    }
  }

  // Refresh data when the app is resumed from background
  Future<void> _refreshAppDataOnResume() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Force a consumption data update
      await _sendConsumptionData(user.uid);
      developer.log("App resumed: refreshed data for user ${user.uid}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(create: (context) => LanguageProvider()),
      ],
      child: Consumer2<ThemeProvider, LanguageProvider>(
        builder: (context, themeProvider, languageProvider, child) {
          return MaterialApp(
            title: 'Energenius',
            theme: themeProvider.themeData,
            themeMode: themeProvider.isDarkTheme ? ThemeMode.dark : ThemeMode.light,
            darkTheme: ThemeProvider.darkTheme,
            themeAnimationDuration: const Duration(milliseconds: 400),
            themeAnimationCurve: Curves.easeInOut,
            locale: languageProvider.locale,
            supportedLocales: const [
              Locale('en', ''), // English
              Locale('ar', ''), // Arabic
              Locale('fr', ''), // French
            ],
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            initialRoute: '/login',
            routes: {
              '/login': (context) => LoginScreen(),
              '/main': (context) => const MainScreen(),
            },
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}