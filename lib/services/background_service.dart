import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../database/database_helper.dart';
import 'dart:developer' as developer;
// Temporarily comment out for building release APK
// import 'background_tasks.dart';

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  // Notification channel details
  static const String notificationChannelId = 'energenius_service_channel';
  static const String notificationChannelName = 'Energenius Energy Tracker';
  static const String notificationTitle = 'Energenius Energy Tracker';
  static const int notificationId = 888;

  // Background task names
  static const String periodicTaskName = 'energenius.periodic.update';
  static const String midnightTaskName = 'energenius.midnight.reset';
  
  // Background service initialization
  Future<void> initializeService() async {
    final service = FlutterBackgroundService();
    
    // Initialize notifications
    await _setupNotifications();
    
    // Initialize Workmanager for persistent background tasks
    // Temporarily comment out for building release APK
    // await BackgroundTasks.initialize();
    
    // Register periodic task that runs even when app is closed
    // Temporarily comment out for building release APK
    // await BackgroundTasks.registerAllTasks();
    
    // Configure the foreground service
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: notificationTitle,
        initialNotificationContent: 'Monitoring device energy consumption',
        foregroundServiceNotificationId: notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }
  
  // Setup notifications
  Future<void> _setupNotifications() async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const androidInitSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInitSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInitSettings,
      iOS: iosInitSettings,
    );
    
    await flutterLocalNotificationsPlugin.initialize(initSettings);
  }
  
  // Start the background service
  static Future<void> onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    
    // For Android, make sure this is a foreground service
    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }
    
    // Store data about active devices and update them periodically
    await _startDeviceTracking(service);
    
    // Setup midnight reset timer
    _setupMidnightResetTimer(service);
    
    // Listen for commands from the main app
    service.on('stopService').listen((event) {
      service.stopSelf();
    });
    
    // Listen for app state changes
    service.on('appStateChanged').listen((event) {
      if (event?['state'] == 'resumed') {
        _handleAppResume(service);
      } else if (event?['state'] == 'paused') {
        _handleAppPause(service);
      }
    });
    
    // Listen for manual data sync requests
    service.on('syncData').listen((event) async {
      if (FirebaseAuth.instance.currentUser != null) {
        final userId = FirebaseAuth.instance.currentUser!.uid;
        await DatabaseHelper.instance.syncAndFillMissingData(userId);
        developer.log("Manual data sync performed for user: $userId");
      }
    });
  }
  
  // Handle app resume event
  static Future<void> _handleAppResume(ServiceInstance service) async {
    try {
      if (FirebaseAuth.instance.currentUser != null) {
        final userId = FirebaseAuth.instance.currentUser!.uid;
        
        // Sync and fill missing data
        await DatabaseHelper.instance.syncAndFillMissingData(userId);
        
        // Re-register background tasks to ensure they're running
        // Temporarily comment out for building release APK
        // await BackgroundTasks.registerAllTasks();
        
        developer.log("Background service handled app resume for user: $userId");
      }
    } catch (e) {
      developer.log("Error handling app resume: $e");
    }
  }
  
  // Handle app pause event
  static Future<void> _handleAppPause(ServiceInstance service) async {
    try {
      if (FirebaseAuth.instance.currentUser != null) {
        final userId = FirebaseAuth.instance.currentUser!.uid;
        
        // Save current timestamp as last active
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('app_last_active', DateTime.now().toIso8601String());
        
        // Force an update of all active devices
        await _updateActiveDevices(userId);
        
        developer.log("Background service handled app pause for user: $userId");
      }
    } catch (e) {
      developer.log("Error handling app pause: $e");
    }
  }
  
  // Start tracking devices and updating their consumption
  static Future<void> _startDeviceTracking(ServiceInstance service) async {
    // First, check if we need to recover from an app closure
    await _recoverFromAppClosure();
    
    // Then start the periodic timer
    Timer.periodic(const Duration(minutes: 2), (timer) async {
      // Check if a user is logged in
      if (FirebaseAuth.instance.currentUser != null) {
        final userId = FirebaseAuth.instance.currentUser!.uid;
        
        try {
          // Update device status
          await _updateActiveDevices(userId);
          
          // Update the notification
          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: notificationTitle,
              content: "Tracking energy consumption (Last update: ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')})",
            );
          }
          
          // Save last update time to shared preferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('last_background_update', DateTime.now().toIso8601String());
          
          // Broadcast an update to the app if it's running
          service.invoke('update', {
            'time': DateTime.now().toIso8601String(),
          });
          
          developer.log("Background service updated devices at ${DateTime.now().toIso8601String()}");
        } catch (e) {
          developer.log("Error in background service: $e");
        }
      }
    });
  }
  
  // Recover from app closure
  static Future<void> _recoverFromAppClosure() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('current_user_id');
      
      if (userId != null) {
        // Check if we missed a midnight reset
        await _checkForMissedMidnightReset(userId);
        
        // Sync and fill missing data
        await DatabaseHelper.instance.syncAndFillMissingData(userId);
        
        // Ensure all devices are properly tracked
        await _updateActiveDevices(userId);
        
        // Re-register background tasks
        // Temporarily comment out for building release APK
        // await BackgroundTasks.registerAllTasks();
        
        developer.log("Recovered from app closure for user: $userId");
      }
    } catch (e) {
      developer.log("Error recovering from app closure: $e");
    }
  }
  
  // Setup midnight reset timer
  static Future<void> _setupMidnightResetTimer(ServiceInstance service) async {
    try {
      // Calculate time until next midnight
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final timeUntilMidnight = tomorrow.difference(now);
      
      // Set a one-time timer to trigger at midnight
      Timer(timeUntilMidnight, () async {
        if (FirebaseAuth.instance.currentUser != null) {
          final userId = FirebaseAuth.instance.currentUser!.uid;
          
          // Reset daily usage
          await DatabaseHelper.instance.checkAndResetDailyUsage(userId);
          developer.log("Midnight reset performed for user: $userId by background service");
          
          // Set up the next day's timer
          _setupMidnightResetTimer(service);
        }
      });
      
      // Store the expected reset time in shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('next_midnight_reset', tomorrow.toIso8601String());
      
      developer.log("Midnight reset timer set for ${timeUntilMidnight.inHours} hours and ${timeUntilMidnight.inMinutes % 60} minutes from now");
    } catch (e) {
      developer.log("Error setting up midnight reset timer: $e");
    }
  }
  
  // Update all active devices' uptime and consumption
  static Future<void> _updateActiveDevices(String userId) async {
    try {
      // First check if reset needed
      await DatabaseHelper.instance.checkAndResetDailyUsage(userId);
      
      // Get all devices
      List<Map<String, dynamic>> devices = await DatabaseHelper.instance.getUserDevices(userId);
      
      // Update each active device
      for (var device in devices) {
        String deviceId = device['id'];
        bool isActive = device['last_active'] != null;
        
        if (isActive) {
          // Update active device's uptime
          await DatabaseHelper.instance.updateDeviceUptime(
            deviceId: deviceId,
            isActive: true,
          );
          developer.log("Background service updated uptime for device: ${device['model']}");
        }
      }
      
      // Send consumption data to update history
      await DatabaseHelper.instance.autoSendConsumptionData(userId);
      
      // Check if we missed a midnight reset
      await _checkForMissedMidnightReset(userId);
    } catch (e) {
      developer.log("Error updating active devices in background: $e");
    }
  }
  
  // Check if we missed a midnight reset
  static Future<void> _checkForMissedMidnightReset(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? nextResetStr = prefs.getString('next_midnight_reset');
      
      if (nextResetStr != null) {
        DateTime nextReset = DateTime.tryParse(nextResetStr) ?? DateTime.now();
        DateTime now = DateTime.now();
        
        // If we're past the scheduled reset time
        if (now.isAfter(nextReset)) {
          // Force a reset
          await DatabaseHelper.instance.checkAndResetDailyUsage(userId);
          
          // Calculate the next reset time
          final tomorrow = DateTime(now.year, now.month, now.day + 1);
          await prefs.setString('next_midnight_reset', tomorrow.toIso8601String());
          
          developer.log("Performed missed midnight reset for user: $userId");
        }
      }
    } catch (e) {
      developer.log("Error checking for missed midnight reset: $e");
    }
  }
  
  // iOS background task
  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }
} 