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

  Future<void> _updateConsumptionHistory(String userId) async {
    try {
      // Calculate total consumption from user-added devices
      List<Map<String, dynamic>> devices = await getDevices(userId);
      double totalConsumption = 0.0;
      for (var device in devices) {
        totalConsumption += (device['power_consumption'] ?? 0) * (device['usage_hours_per_day'] ?? 0);
      }

      String today = DateTime.now().toIso8601String().split('T')[0];
      DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .doc(today)
          .get();

      if (!doc.exists) {
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
      }

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .doc(today)
          .update({
        'total_consumption': totalConsumption,
      });

      DateTime thirtyDaysAgo = DateTime.now().subtract(Duration(days: 30));
      QuerySnapshot oldDocs = await _firestore
          .collection('users')
          .doc(userId)
          .collection('consumption_history')
          .orderBy('date')
          .startAfter([thirtyDaysAgo.toIso8601String().split('T')[0]])
          .get();

      WriteBatch cleanupBatch = _firestore.batch();
      int cleanupBatchCount = 0;
      for (var doc in oldDocs.docs) {
        String docDate = doc.id;
        DateTime docDateTime = DateTime.parse(docDate);
        if (docDateTime.isBefore(thirtyDaysAgo)) {
          cleanupBatch.delete(doc.reference);
          cleanupBatchCount++;
          if (cleanupBatchCount >= 500) {
            await cleanupBatch.commit();
            cleanupBatch = _firestore.batch();
            cleanupBatchCount = 0;
          }
        }
      }

      if (cleanupBatchCount > 0) {
        await cleanupBatch.commit();
        developer.log("Cleaned up old consumption history for user $userId");
      }

      developer.log("Updated consumption history for $today: $totalConsumption kWh for user $userId");
    } catch (e) {
      developer.log("Error updating consumption history: $e");
    }
  }
}