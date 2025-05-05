import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DatabaseHelper._privateConstructor();

  // Fetch devices for a specific user
  Future<List<Map<String, dynamic>>> getDevices(String userId) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('devices')
          .where('is_user_added', isEqualTo: 1)
          .where('user_id', isEqualTo: userId)
          .get();

      return snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id; // Include the document ID
        return data;
      }).toList();
    } catch (e) {
      developer.log("Error fetching devices for user $userId: $e");
      return [];
    }
  }

  // Alias for getDevices to maintain compatibility with code that used DatabaseAdapter
  Future<List<Map<String, dynamic>>> getUserDevices(String userId) async {
    return getDevices(userId);
  }

  // Fetch all categories
  Future<List<Map<String, dynamic>>> getCategories() async {
    try {
      QuerySnapshot snapshot = await _firestore.collection('categories').get();
      return snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id; // Include the document ID
        return data;
      }).toList();
    } catch (e) {
      developer.log("Error fetching categories: $e");
      return [];
    }
  }

  // Fetch preset devices (not user-added)
  Future<List<Map<String, dynamic>>> getPresetDevices() async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('devices')
          .where('is_user_added', isEqualTo: 0)
          .get();

      return snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id; // Include the document ID
        return data;
      }).toList();
    } catch (e) {
      developer.log("Error fetching preset devices: $e");
      return [];
    }
  }

  Future<void> addUserDevice({
    required String userId,
    required int categoryId,
    required String manufacturer,
    required String model,
    required double powerConsumption,
    double usageHoursPerDay = 0,
  }) async {
    try {
      // Check for an existing preset device with matching attributes
      QuerySnapshot presetSnapshot = await _firestore
          .collection('devices')
          .where('manufacturer', isEqualTo: manufacturer)
          .where('model', isEqualTo: model)
          .where('power_consumption', isEqualTo: powerConsumption)
          .where('is_user_added', isEqualTo: 0)
          .limit(1)
          .get();

      if (presetSnapshot.docs.isNotEmpty) {
        String existingDeviceId = presetSnapshot.docs.first.id;
        await _firestore.collection('devices').doc(existingDeviceId).update({
          'is_user_added': 1,
          'user_id': userId,
          'usage_hours_per_day': usageHoursPerDay,
        });
        await _updateConsumptionHistory(userId);
        developer.log("Updated existing preset device ID $existingDeviceId for user $userId");
      } else {
        await _firestore.collection('devices').add({
          'category_id': categoryId,
          'manufacturer': manufacturer,
          'model': model,
          'power_consumption': powerConsumption,
          'usage_hours_per_day': usageHoursPerDay,
          'is_user_added': 1,
          'user_id': userId,
        });
        await _updateConsumptionHistory(userId);
        developer.log("Added new user device: $model for user $userId");
      }
    } catch (e) {
      developer.log("Error adding device to Firestore: $e");
      rethrow;
    }
  }

  Future<void> updateUserDevice({
    required String deviceId,
    required String userId,
    required int categoryId,
    required String manufacturer,
    required String model,
    required double powerConsumption,
    required double usageHoursPerDay,
  }) async {
    try {
      await _firestore.collection('devices').doc(deviceId).update({
        'category_id': categoryId,
        'manufacturer': manufacturer,
        'model': model,
        'power_consumption': powerConsumption,
        'usage_hours_per_day': usageHoursPerDay,
        'is_user_added': 1,
        'user_id': userId,
      });
      await _updateConsumptionHistory(userId);
      developer.log("Updated device ID $deviceId in Firestore");
    } catch (e) {
      developer.log("Error updating device in Firestore: $e");
      rethrow;
    }
  }

  Future<void> deleteUserDevice(String deviceId, String userId) async {
    try {
      await _firestore.collection('devices').doc(deviceId).delete();
      await _updateConsumptionHistory(userId);
      developer.log("Deleted device ID $deviceId from Firestore");
    } catch (e) {
      developer.log("Error deleting device from Firestore: $e");
      rethrow;
    }
  }

  // Initialize consumption history for a new user
  Future<void> initializeUserConsumption(String userId) async {
    try {
      String today = DateTime.now().toIso8601String().split('T')[0];
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .doc(today)
          .set({
        'date': today,
        'total_consumption': 0.0,
        'timestamp': FieldValue.serverTimestamp(),
      });
      
      developer.log("Initialized consumption history for new user $userId");
    } catch (e) {
      developer.log("Error initializing consumption history: $e");
      rethrow;
    }
  }
  
  // Method to ensure historical data exists - only checks, doesn't generate fake data
  Future<void> ensureHistoricalData(String userId) async {
    try {
      // Check if we have historical data
      QuerySnapshot snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .orderBy('date', descending: true)
          .limit(1)
          .get();
          
      if (snapshot.docs.isEmpty) {
        // No historical data, but we'll let it be empty rather than creating fake data
        developer.log("No historical consumption data found for user $userId");
      }
    } catch (e) {
      developer.log("Error checking historical data: $e");
    }
  }

  Future<void> _updateConsumptionHistory(String userId) async {
    try {
      // Calculate total consumption from user-added devices
      List<Map<String, dynamic>> devices = await getDevices(userId);
      double totalDailyConsumption = 0.0;
      
      // Calculate total consumption based on all devices' power and usage hours
      for (var device in devices) {
        double devicePower = device['power_consumption'] ?? 0.0;
        double usageHours = device['usage_hours_per_day'] ?? 0.0;
        totalDailyConsumption += devicePower * usageHours;
      }

      String today = DateTime.now().toIso8601String().split('T')[0];
      DocumentReference docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .doc(today);
          
      DocumentSnapshot doc = await docRef.get();

      if (!doc.exists) {
        // Create a new document for today if it doesn't exist
        await docRef.set({
          'date': today,
          'total_consumption': totalDailyConsumption,
          'timestamp': FieldValue.serverTimestamp(),
          'hourly_consumption': {},
          'devices_consumption': {},
        });
        developer.log("Created new consumption document for $today: $totalDailyConsumption kWh");
      } else {
        // Update the daily total consumption
        await docRef.update({
          'total_consumption': totalDailyConsumption,
          'last_updated': FieldValue.serverTimestamp(),
        });
        developer.log("Updated consumption history for $today: $totalDailyConsumption kWh");
      }

      // Record hourly consumption data with improved time-of-day based usage patterns
      await _recordHourlyConsumption(userId, totalDailyConsumption);
      
      // Refresh 7 days of history to ensure data consistency
      await _refreshRecentHistoryTotals(userId);

      developer.log("Updated consumption history for $today: $totalDailyConsumption kWh for user $userId");
    } catch (e) {
      developer.log("Error updating consumption history: $e");
    }
  }
  
  // New method to refresh recent history totals
  Future<void> _refreshRecentHistoryTotals(String userId) async {
    try {
      // Get the last 7 days of consumption history
      String today = DateTime.now().toIso8601String().split('T')[0];
      String sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7)).toIso8601String().split('T')[0];
      
      QuerySnapshot snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .where('date', isGreaterThanOrEqualTo: sevenDaysAgo)
          .where('date', isLessThanOrEqualTo: today)
          .get();
          
      // Update each document with recalculated totals based on hourly data
      for (var doc in snapshot.docs) {
        if (doc.id == today) continue; // Skip today as it's already being updated
        
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        
        if (data.containsKey('hourly_consumption')) {
          Map<String, dynamic> hourlyData = Map<String, dynamic>.from(data['hourly_consumption']);
          
          // Recalculate total consumption from hourly data
          double recalculatedTotal = 0.0;
          hourlyData.forEach((hour, value) {
            recalculatedTotal += (value as num).toDouble();
          });
          
          // Update the document with the recalculated total
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('consumption_history')
              .doc(doc.id)
              .update({
                'total_consumption': recalculatedTotal,
                'last_updated': FieldValue.serverTimestamp(),
              });
              
          developer.log("Refreshed consumption total for ${doc.id}: $recalculatedTotal kWh");
        }
      }
    } catch (e) {
      developer.log("Error refreshing history totals: $e");
    }
  }

  // Record hourly consumption data with improved time-of-day based usage patterns
  Future<void> _recordHourlyConsumption(String userId, double totalDailyConsumption) async {
    try {
      String today = DateTime.now().toIso8601String().split('T')[0];
      int currentHour = DateTime.now().hour;
      
      // Get the devices and calculate hourly consumption based on actual usage
      List<Map<String, dynamic>> devices = await getDevices(userId);
      
      // If we have no devices, hourly consumption is zero
      if (devices.isEmpty) {
        return;
      }
      
      // Define usage patterns based on time of day
      // These coefficients represent typical home energy usage patterns
      Map<int, double> hourlyPatterns = {
        0: 0.4,  // 12 AM - low usage (sleeping)
        1: 0.3,
        2: 0.3,
        3: 0.3,
        4: 0.3,
        5: 0.5,  // 5 AM - starting to wake up
        6: 0.8,  // Morning routines begin
        7: 1.2,  // Morning peak (breakfast, showers)
        8: 1.3,
        9: 1.0,  // People leaving for work/school
        10: 0.8,
        11: 0.7,
        12: 0.9,  // Noon - lunch time
        13: 0.8,
        14: 0.7,
        15: 0.7,
        16: 0.8,
        17: 1.2,  // 5 PM - returning home
        18: 1.5,  // Evening peak (dinner preparation)
        19: 1.8,  // Peak evening usage
        20: 1.7,  // High evening usage
        21: 1.4,  // Starting to wind down
        22: 1.0,  // Getting ready for bed
        23: 0.6   // Late night, reduced usage
      };
      
      // Calculate hourly consumption for current hour based on device usage and patterns
      double hourlyConsumption = 0.0;
      Map<String, double> deviceContributions = {};
      
      for (var device in devices) {
        double devicePower = device['power_consumption'] ?? 0.0;
        double hoursPerDay = device['usage_hours_per_day'] ?? 0.0;
        String deviceId = device['id'] ?? '';
        
        // Calculate this device's contribution to the current hour using the pattern
        if (hoursPerDay > 0) {
          // Apply the hourly pattern coefficient
          double hourlyUsage = devicePower * (hoursPerDay / 24) * (hourlyPatterns[currentHour] ?? 1.0);
          hourlyConsumption += hourlyUsage;
          
          // Store the individual device contribution
          if (deviceId.isNotEmpty) {
            deviceContributions[deviceId] = hourlyUsage;
          }
        }
      }
      
      // Get reference to the hourly consumption collection
      DocumentReference dailyDocRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .doc(today);
      
      // First get existing hourly data, if any
      DocumentSnapshot doc = await dailyDocRef.get();
      Map<String, dynamic> existingHourlyData = {};
      Map<String, dynamic> existingDevicesConsumption = {};
      
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        if (data.containsKey('hourly_consumption')) {
          existingHourlyData = Map<String, dynamic>.from(data['hourly_consumption']);
        }
        if (data.containsKey('devices_consumption')) {
          existingDevicesConsumption = Map<String, dynamic>.from(data['devices_consumption']);
        }
      }
      
      // Add current hour data to existing data
      existingHourlyData[currentHour.toString()] = hourlyConsumption;
      
      // Update device-specific consumption data
      deviceContributions.forEach((deviceId, consumption) {
        if (!existingDevicesConsumption.containsKey(deviceId)) {
          // If this is the first record for this device today, initialize its data
          var device = devices.firstWhere((d) => d['id'] == deviceId, orElse: () => {});
          existingDevicesConsumption[deviceId] = {
            'manufacturer': device['manufacturer'] ?? 'Unknown',
            'model': device['model'] ?? 'Device',
            'daily_consumption': consumption,
            'hourly_data': {currentHour.toString(): consumption}
          };
        } else {
          // Update existing device data
          Map<String, dynamic> deviceData = Map<String, dynamic>.from(existingDevicesConsumption[deviceId]);
          
          // Get the hourly data for this device
          Map<String, dynamic> hourlyData = 
              deviceData.containsKey('hourly_data') ? 
              Map<String, dynamic>.from(deviceData['hourly_data']) : 
              {};
          
          // Update the current hour's consumption
          hourlyData[currentHour.toString()] = consumption;
          
          // Recalculate the total daily consumption by summing all hourly values
          double recalculatedDailyTotal = 0.0;
          hourlyData.forEach((hour, value) {
            recalculatedDailyTotal += (value as num).toDouble();
          });
          
          // Update the device data with new values
          deviceData['hourly_data'] = hourlyData;
          deviceData['daily_consumption'] = recalculatedDailyTotal;
          
          existingDevicesConsumption[deviceId] = deviceData;
        }
      });
      
      // Calculate the total daily consumption based on recorded hourly data
      double calculatedDailyTotal = 0.0;
      existingHourlyData.forEach((hour, value) {
        calculatedDailyTotal += (value as num).toDouble();
      });
      
      // Update hourly consumption data in the daily document
      await dailyDocRef.set({
        'hourly_consumption': existingHourlyData,
        'devices_consumption': existingDevicesConsumption,
        'total_consumption': calculatedDailyTotal,
        'date': today,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      developer.log("Recorded hourly consumption for hour $currentHour: $hourlyConsumption kWh, total daily: $calculatedDailyTotal kWh");
    } catch (e) {
      developer.log("Error recording hourly consumption: $e");
    }
  }

  // Get hourly consumption for a specific day with enhanced device breakdown
  Future<Map<String, dynamic>> getHourlyConsumptionEnhanced(String userId, String date) async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .doc(date)
          .get();
          
      Map<int, double> hourlyData = {};
      Map<String, dynamic> deviceData = {};
      double totalConsumption = 0.0;
      
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        totalConsumption = (data['total_consumption'] ?? 0.0).toDouble();
        
        if (data.containsKey('hourly_consumption')) {
          Map<String, dynamic> hourlyConsumption = data['hourly_consumption'];
          hourlyConsumption.forEach((hour, consumption) {
            hourlyData[int.parse(hour)] = consumption.toDouble();
          });
        }
        
        if (data.containsKey('devices_consumption')) {
          deviceData = Map<String, dynamic>.from(data['devices_consumption']);
        }
      }
      
      return {
        'hourly_data': hourlyData,
        'devices_data': deviceData,
        'total_consumption': totalConsumption,
        'date': date
      };
    } catch (e) {
      developer.log("Error getting enhanced hourly consumption: $e");
      return {
        'hourly_data': <int, double>{},
        'devices_data': <String, dynamic>{},
        'total_consumption': 0.0,
        'date': date
      };
    }
  }
  
  // Auto-send consumption data to the database periodically
  // This can be called from the app's background service
  Future<void> autoSendConsumptionData(String userId) async {
    try {
      await _updateConsumptionHistory(userId);
      developer.log("Auto-sent consumption data for user: $userId");
    } catch (e) {
      developer.log("Error auto-sending consumption data: $e");
    }
  }
  
  // Method to record device usage at regular intervals
  Future<void> recordDeviceUsage(String userId) async {
    try {
      // This method would be called by a background service or timer
      // to regularly update the consumption data
      await _updateConsumptionHistory(userId);
      developer.log("Recorded device usage for user: $userId");
    } catch (e) {
      developer.log("Error recording device usage: $e");
    }
  }
  
  // Get daily consumption data for a date range
  Future<List<Map<String, dynamic>>> getDailyConsumption(String userId, DateTime startDate, DateTime endDate) async {
    try {
      String startDateStr = startDate.toIso8601String().split('T')[0];
      String endDateStr = endDate.toIso8601String().split('T')[0];
      
      QuerySnapshot snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .where('date', isGreaterThanOrEqualTo: startDateStr)
          .where('date', isLessThanOrEqualTo: endDateStr)
          .orderBy('date')
          .get();
          
      return snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      developer.log("Error getting daily consumption: $e");
      return [];
    }
  }
  
  // Get weekly consumption data
  Future<List<Map<String, dynamic>>> getWeeklyConsumption(String userId, DateTime startDate, DateTime endDate) async {
    // For weekly data, we'll just get daily data and let the UI aggregate it
    return getDailyConsumption(userId, startDate, endDate);
  }
  
  // Get monthly consumption data
  Future<List<Map<String, dynamic>>> getMonthlyConsumption(String userId, DateTime startDate, DateTime endDate) async {
    // For monthly data, we'll just get daily data and let the UI aggregate it
    return getDailyConsumption(userId, startDate, endDate);
  }

  // Initialize for the current user (compatibility method)
  Future<void> initialize(String userId) async {
    try {
      // Ensure the user has consumption history
      await ensureHistoricalData(userId);
      developer.log("Database initialized for user: $userId");
    } catch (e) {
      developer.log("Error initializing database: $e");
    }
  }
  
  // Force migration stub (compatibility method)
  Future<bool> forceMigration(String userId) async {
    // No actual migration needed anymore
    return true;
  }

  // Get hourly consumption for a specific day (original method for backward compatibility)
  Future<Map<int, double>> getHourlyConsumption(String userId, String date) async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .doc(date)
          .get();
          
      Map<int, double> hourlyData = {};
      
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        if (data.containsKey('hourly_consumption')) {
          Map<String, dynamic> hourlyConsumption = data['hourly_consumption'];
          hourlyConsumption.forEach((hour, consumption) {
            hourlyData[int.parse(hour)] = consumption.toDouble();
          });
        }
      }
      
      return hourlyData;
    } catch (e) {
      developer.log("Error getting hourly consumption: $e");
      return {};
    }
  }
}