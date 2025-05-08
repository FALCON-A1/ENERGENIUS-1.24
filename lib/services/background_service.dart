import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../database/database_helper.dart';
import 'dart:developer' as developer;

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  // Notification channel details
  static const String notificationChannelId = 'energenius_service_channel';
  static const String notificationChannelName = 'Energenius Background Service';
  static const String notificationTitle = 'Energenius Energy Tracker';
  static const int notificationId = 888;

  // Timer for periodic updates
  Timer? _deviceUpdateTimer;
  
  // Background service initialization
  Future<void> initializeService() async {
    final service = FlutterBackgroundService();
    
    // Initialize notifications
    await _setupNotifications();
    
    // Configure the service
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
    
    // Listen for commands from the main app
    service.on('stopService').listen((event) {
      service.stopSelf();
    });
  }
  
  // Start tracking devices and updating their consumption
  static Future<void> _startDeviceTracking(ServiceInstance service) async {
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
    } catch (e) {
      developer.log("Error updating active devices in background: $e");
    }
  }
  
  // iOS background task
  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }
} 