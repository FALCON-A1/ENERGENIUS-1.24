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
    
    // Set up auth state listener to handle database operations on auth changes
    _setupAuthListener();
    
  } catch (e) {
    developer.log("Error initializing Firebase: $e");
  }
  runApp(const MyApp());
}

// Timer to periodically send consumption data to the database
Timer? _consumptionDataTimer;

void _startConsumptionDataTimer(String userId) {
  // Cancel any existing timer
  _consumptionDataTimer?.cancel();
  
  // Create a new timer that runs every 10 minutes
  _consumptionDataTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
    _sendConsumptionData(userId);
  });
  
  // Also send data immediately on app start
  _sendConsumptionData(userId);
  
  developer.log("Started consumption data timer for user: $userId");
}

Future<void> _sendConsumptionData(String userId) async {
  try {
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
      developer.log("Auth state changed: User signed out");
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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