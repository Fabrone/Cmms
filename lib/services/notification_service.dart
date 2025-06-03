import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/notification_model.dart';
import 'package:cmms/models/maintenance_task_model.dart';
import 'package:cmms/developer/notification_setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb; 

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final Logger _logger = Logger();

  // Notification counter stream
  static const String _notificationCountKey = 'notification_count';
  
  // Initialize notification service
  Future<void> initialize() async {
    await _initializeLocalNotifications();
    await _initializeFCM();
    await _requestNotificationPermissions();
    await _setupNotificationListeners();
    
    // Check for due notifications on startup
    await checkForDueNotifications();
    
    // Set up periodic check for due notifications
    Timer.periodic(const Duration(hours: 1), (_) {
      checkForDueNotifications();
    });
  }

  Future<void> _requestNotificationPermissions() async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channel for Android with proper theming
    const androidChannel = AndroidNotificationChannel(
      'maintenance_channel',
      'Maintenance Notifications',
      description: 'Notifications for maintenance task reminders',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      ledColor: Colors.blueGrey, // BlueGrey color
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  // UPDATED METHOD - This is the key fix for your web issue
  Future<void> _initializeFCM() async {
    try {
      String? token;
      
      if (kIsWeb) {
        // For web platform, handle VAPID key and permission checking
        try {
          const vapidKey = 'BJr44Q87YwuvqcYpKTyV_fMt3lvtUSHtOr60R2U5vpnLHx8YZLf84m8DqQB_YNoRt_v1CuYHzbnyUt9-z99TzS4'; 
          
          // Check if VAPID key is configured
          if (vapidKey != 'BJr44Q87YwuvqcYpKTyV_fMt3lvtUSHtOr60R2U5vpnLHx8YZLf84m8DqQB_YNoRt_v1CuYHzbnyUt9-z99TzS4' && vapidKey.isNotEmpty) {
            token = await _messaging.getToken(vapidKey: vapidKey);
          } else {
            // Try without VAPID key (may work in some cases)
            token = await _messaging.getToken();
          }
        } catch (e) {
          _logger.w('Failed to get FCM token for web: $e');
          // Continue execution without token - app should still work
          token = null;
        }
      } else {
        // For mobile platforms (Android/iOS)
        try {
          token = await _messaging.getToken();
        } catch (e) {
          _logger.w('Failed to get FCM token for mobile: $e');
          token = null;
        }
      }
      
      if (token != null) {
        _logger.i('FCM Token: $token');
        
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await _firestore.collection('Users').doc(user.uid).set({
            'fcmToken': token,
            'lastTokenUpdate': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } else {
        _logger.w('FCM Token is null - notifications may not work properly');
      }

      // Set up token refresh listener with error handling
      _messaging.onTokenRefresh.listen((newToken) async {
        _logger.i('FCM token refreshed: $newToken');
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          try {
            await _firestore.collection('Users').doc(user.uid).update({
              'fcmToken': newToken,
              'lastTokenUpdate': FieldValue.serverTimestamp(),
            });
          } catch (e) {
            _logger.e('Error updating refreshed token: $e');
          }
        }
      }).onError((error) {
        _logger.e('Error in token refresh listener: $error');
      });
      
    } catch (e) {
      _logger.e('Error in FCM initialization: $e');
      // Don't rethrow - let the app continue without FCM
    }
  }

  Future<void> _setupNotificationListeners() async {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    
    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);

    // Handle notification taps when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Handle notification tap when app is terminated
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    _logger.i('Local notification tapped: ${response.payload}');
    resetNotificationCount();
  }

  void _handleNotificationTap(RemoteMessage message) {
    _logger.i('FCM notification tapped: ${message.data}');
    resetNotificationCount();
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    _logger.i('Foreground message: ${message.notification?.title}');
    
    // Increment notification count
    await _incrementNotificationCount();
    
    // Show local notification when app is in foreground with proper theming
    await _showLocalNotification(
      title: message.notification?.title ?? 'Maintenance Reminder',
      body: message.notification?.body ?? 'You have maintenance tasks to check',
      payload: message.data['notificationId'],
    );
  }

  static Future<void> _handleBackgroundMessage(RemoteMessage message) async {
    Logger().i('Background message: ${message.notification?.title}');
    // Increment notification count for background messages
    final prefs = await SharedPreferences.getInstance();
    final currentCount = prefs.getInt(_notificationCountKey) ?? 0;
    await prefs.setInt(_notificationCountKey, currentCount + 1);
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'maintenance_channel',
      'Maintenance Notifications',
      channelDescription: 'Notifications for maintenance task reminders',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/launcher_icon',
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/launcher_icon'),
      color: Colors.blueGrey, // BlueGrey color
      enableVibration: true,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('notification'),
      enableLights: true,
      ledColor: Colors.blueGrey,
      ledOnMs: 1000,
      ledOffMs: 500,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
    );
    
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      payload: payload,
    );
  }

  // Notification count management
  Future<void> _incrementNotificationCount() async {
    final prefs = await SharedPreferences.getInstance();
    final currentCount = prefs.getInt(_notificationCountKey) ?? 0;
    await prefs.setInt(_notificationCountKey, currentCount + 1);
  }

  // Public method to increment notification count (called from main.dart)
  Future<void> incrementNotificationCount() async {
    await _incrementNotificationCount();
  }

  Future<void> resetNotificationCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_notificationCountKey, 0);
  }

  Future<int> getNotificationCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_notificationCountKey) ?? 0;
  }

  Stream<int> getNotificationCountStream() async* {
    while (true) {
      yield await getNotificationCount();
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  // Calculate notification dates
  Map<String, DateTime> calculateNotificationDates({
    required DateTime lastInspectionDate,
    required int frequencyMonths,
  }) {
    final daysInFrequency = frequencyMonths * 30;
    final nextInspectionDate = lastInspectionDate.add(Duration(days: daysInFrequency));
    final notificationDate = nextInspectionDate.subtract(const Duration(days: 5));

    return {
      'nextInspectionDate': nextInspectionDate,
      'notificationDate': notificationDate,
    };
  }

  // Schedule a notification for a maintenance task
  Future<String> scheduleNotification({
    required String category,
    required String component,
    required String intervention,
    required DateTime notificationDate,
    required String facilityId,
    required String taskId,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final notification = NotificationModel(
        id: '',
        taskId: taskId,
        category: category,
        component: component,
        intervention: intervention,
        frequency: 1, // Default frequency
        lastInspectionDate: DateTime.now(),
        nextInspectionDate: notificationDate,
        notificationDate: notificationDate,
        assignedTechnicians: [],
        createdAt: DateTime.now(),
        createdBy: user.uid,
      );

      // Check if there's already a grouped notification for this date
      final existingGroupQuery = await _firestore
          .collection('Notifications')
          .where('notificationDate', isEqualTo: Timestamp.fromDate(notificationDate))
          .limit(1)
          .get();

      String notificationId;
      if (existingGroupQuery.docs.isNotEmpty) {
        // Add to existing group
        final existingDoc = existingGroupQuery.docs.first;
        final existingGroup = GroupedNotificationModel.fromFirestore(existingDoc);
        
        final updatedNotifications = [...existingGroup.notifications, notification];
        final updatedGroup = GroupedNotificationModel(
          notificationDate: existingGroup.notificationDate,
          notifications: updatedNotifications,
          isTriggered: false,
        );

        await existingDoc.reference.update(updatedGroup.toMap());
        notificationId = existingDoc.id;
      } else {
        // Create new group
        final newGroup = GroupedNotificationModel(
          notificationDate: notificationDate,
          notifications: [notification],
          isTriggered: false,
        );

        final docRef = await _firestore.collection('Notifications').add(newGroup.toMap());
        notificationId = docRef.id;
      }

      _logger.i('Scheduled notification for task: $taskId, facility: $facilityId, date: $notificationDate');
      return notificationId;
    } catch (e) {
      _logger.e('Error scheduling notification: $e');
      rethrow;
    }
  }

  // Create notification for a maintenance task
  Future<String> createNotification({
    required MaintenanceTaskModel task,
    required String taskId,
    required DateTime lastInspectionDate,
    required List<String> assignedTechnicians,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final dates = calculateNotificationDates(
        lastInspectionDate: lastInspectionDate,
        frequencyMonths: task.frequency,
      );

      final notification = NotificationModel(
        id: '',
        taskId: taskId,
        category: task.category,
        component: task.component,
        intervention: task.intervention,
        frequency: task.frequency,
        lastInspectionDate: lastInspectionDate,
        nextInspectionDate: dates['nextInspectionDate']!,
        notificationDate: dates['notificationDate']!,
        assignedTechnicians: assignedTechnicians,
        createdAt: DateTime.now(),
        createdBy: user.uid,
      );

      // Check if there's already a grouped notification for this date
      final existingGroupQuery = await _firestore
          .collection('Notifications')
          .where('notificationDate', isEqualTo: Timestamp.fromDate(dates['notificationDate']!))
          .limit(1)
          .get();

      String notificationId;
      if (existingGroupQuery.docs.isNotEmpty) {
        // Add to existing group
        final existingDoc = existingGroupQuery.docs.first;
        final existingGroup = GroupedNotificationModel.fromFirestore(existingDoc);
        
        final updatedNotifications = [...existingGroup.notifications, notification];
        final updatedGroup = GroupedNotificationModel(
          notificationDate: existingGroup.notificationDate,
          notifications: updatedNotifications,
          isTriggered: false,
        );

        await existingDoc.reference.update(updatedGroup.toMap());
        notificationId = existingDoc.id;
      } else {
        // Create new group
        final newGroup = GroupedNotificationModel(
          notificationDate: dates['notificationDate']!,
          notifications: [notification],
          isTriggered: false,
        );

        final docRef = await _firestore.collection('Notifications').add(newGroup.toMap());
        notificationId = docRef.id;
      }

      return notificationId;
    } catch (e) {
      _logger.e('Error creating notification: $e');
      rethrow;
    }
  }

  // Create grouped notification for multiple categories
  Future<String> createGroupedNotification({
    required List<CategoryInfo> categories,
    required DateTime lastInspectionDate,
    required List<String> assignedTechnicians,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Use the shortest frequency among selected categories for notification timing
      final shortestFrequency = categories
          .map((c) => c.frequency)
          .reduce((a, b) => a < b ? a : b);

      final dates = calculateNotificationDates(
        lastInspectionDate: lastInspectionDate,
        frequencyMonths: shortestFrequency,
      );

      // Create notifications for all tasks in selected categories
      final List<NotificationModel> notifications = [];
      
      for (final categoryInfo in categories) {
        for (final task in categoryInfo.tasks) {
          final notification = NotificationModel(
            id: '',
            taskId: '',
            category: task.category,
            component: task.component,
            intervention: task.intervention,
            frequency: task.frequency,
            lastInspectionDate: lastInspectionDate,
            nextInspectionDate: dates['nextInspectionDate']!,
            notificationDate: dates['notificationDate']!,
            assignedTechnicians: assignedTechnicians,
            createdAt: DateTime.now(),
            createdBy: user.uid,
          );
          notifications.add(notification);
        }
      }

      // Check if there's already a grouped notification for this date
      final existingGroupQuery = await _firestore
          .collection('Notifications')
          .where('notificationDate', isEqualTo: Timestamp.fromDate(dates['notificationDate']!))
          .limit(1)
          .get();

      String notificationId;
      if (existingGroupQuery.docs.isNotEmpty) {
        // Add to existing group
        final existingDoc = existingGroupQuery.docs.first;
        final existingGroup = GroupedNotificationModel.fromFirestore(existingDoc);
        
        final updatedNotifications = [...existingGroup.notifications, ...notifications];
        final updatedGroup = GroupedNotificationModel(
          notificationDate: existingGroup.notificationDate,
          notifications: updatedNotifications,
          isTriggered: false,
        );

        await existingDoc.reference.update(updatedGroup.toMap());
        notificationId = existingDoc.id;
      } else {
        // Create new group
        final newGroup = GroupedNotificationModel(
          notificationDate: dates['notificationDate']!,
          notifications: notifications,
          isTriggered: false,
        );

        final docRef = await _firestore.collection('Notifications').add(newGroup.toMap());
        notificationId = docRef.id;
      }

      return notificationId;
    } catch (e) {
      _logger.e('Error creating grouped notification: $e');
      rethrow;
    }
  }

  // Get all technician user IDs
  Future<List<String>> getTechnicianIds() async {
    try {
      final techniciansSnapshot = await _firestore.collection('Technicians').get();
      return techniciansSnapshot.docs.map((doc) => doc.id).toList();
    } catch (e) {
      _logger.e('Error getting technician IDs: $e');
      return [];
    }
  }

  // Get pending notifications for a user
  Stream<List<GroupedNotificationModel>> getPendingNotifications() {
    return _firestore
        .collection('Notifications')
        .orderBy('notificationDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GroupedNotificationModel.fromFirestore(doc))
            .toList());
  }

  // Get received notifications (triggered ones)
  Stream<List<GroupedNotificationModel>> getReceivedNotifications() {
    return _firestore
        .collection('Notifications')
        .where('isTriggered', isEqualTo: true)
        .orderBy('notificationDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GroupedNotificationModel.fromFirestore(doc))
            .toList());
  }

  // Get setup notifications (all notifications with their status)
  Stream<List<GroupedNotificationModel>> getSetupNotifications() {
    return _firestore
        .collection('Notifications')
        .orderBy('notificationDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GroupedNotificationModel.fromFirestore(doc))
            .toList());
  }

  // Manual trigger for testing
  Future<void> triggerTestNotification() async {
    try {
      const title = 'Test Maintenance Reminder';
      const body = 'This is a test notification for maintenance tasks.';

      // Show local notification
      await _showLocalNotification(
        title: title,
        body: body,
      );

      // Increment notification count
      await _incrementNotificationCount();

      _logger.i('Test notification triggered');
    } catch (e) {
      _logger.e('Error sending test notification: $e');
    }
  }

  // Get today's triggered notifications only (for floating widget)
  Stream<List<GroupedNotificationModel>> getTodaysTriggeredNotifications() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    return _firestore
        .collection('Notifications')
        .where('notificationDate', isEqualTo: Timestamp.fromDate(today))
        .where('isTriggered', isEqualTo: true)
        .orderBy('triggeredAt', descending: true)
        .limit(1) // Only get the latest notification for today
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GroupedNotificationModel.fromFirestore(doc))
            .toList());
  }

  // Get urgent notifications for widget display (deprecated - use getTodaysTriggeredNotifications)
  Stream<List<GroupedNotificationModel>> getUrgentNotifications() {
    return getTodaysTriggeredNotifications();
  }

  // Add a new method to get both scheduled and received notifications
  Stream<List<GroupedNotificationModel>> getAllNotifications() {
    return _firestore
        .collection('Notifications')
        .orderBy('notificationDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GroupedNotificationModel.fromFirestore(doc))
            .toList());
  }

  // Add a method to check for due notifications that haven't been triggered
  Future<void> checkForDueNotifications() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      final dueNotificationsSnapshot = await _firestore
          .collection('Notifications')
          .where('notificationDate', isLessThanOrEqualTo: Timestamp.fromDate(today))
          .where('isTriggered', isEqualTo: false)
          .get();
      
      if (dueNotificationsSnapshot.docs.isNotEmpty) {
        _logger.i('Found ${dueNotificationsSnapshot.docs.length} due notifications that need to be triggered');
      
        // Call the cloud function to trigger these notifications
        try {
          final functions = FirebaseFunctions.instance;
          final result = await functions.httpsCallable('triggerNotificationsManually').call();
          _logger.i('Manual trigger result: ${result.data}');
        } catch (e) {
          _logger.e('Error calling cloud function: $e');
        }
      }
    } catch (e) {
      _logger.e('Error checking for due notifications: $e');
    }
  }
}
