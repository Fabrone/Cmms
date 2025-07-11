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

  // Notification settings keys
  static const String _notificationCountKey = 'notification_count';
  static const String _notificationEnabledKey = 'notifications_enabled';
  
  // Timer for periodic checks
  Timer? _periodicTimer;
  
  // Initialize notification service
  Future<void> initialize() async {
    await _initializeLocalNotifications();
    await _initializeFCM();
    await _requestNotificationPermissions();
    await _setupNotificationListeners();
    
    // Check for due notifications on startup
    await checkForDueNotifications();
    
    // Set up periodic check every hour
    _periodicTimer = Timer.periodic(const Duration(hours: 1), (_) {
      checkForDueNotifications();
    });
  }

  Future<bool> areNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationEnabledKey) ?? true;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationEnabledKey, enabled);
    
    // Update user document in Firestore
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await _firestore.collection('Users').doc(user.uid).update({
          'notificationsEnabled': enabled,
          'lastSettingsUpdate': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        _logger.e('Error updating notification settings in Firestore: $e');
      }
    }
    
    if (!enabled) {
      // Cancel all pending notifications
      await _localNotifications.cancelAll();
      await resetNotificationCount();
    }
  }

  Future<void> _requestNotificationPermissions() async {
    if (kIsWeb) {
      try {
        final permission = await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        
        if (permission.authorizationStatus == AuthorizationStatus.authorized) {
          _logger.i('Web notification permission granted');
        } else {
          _logger.w('Web notification permission denied');
        }
      } catch (e) {
        _logger.e('Error requesting web notification permission: $e');
      }
    } else {
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
  }

  Future<void> _initializeLocalNotifications() async {
    if (kIsWeb) return;

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

    // Create notification channel for Android
    const androidChannel = AndroidNotificationChannel(
      'maintenance_channel',
      'Maintenance Notifications',
      description: 'Notifications for maintenance task reminders',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      ledColor: Colors.blueGrey,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  Future<void> _initializeFCM() async {
    try {
      String? token;
      
      if (kIsWeb) {
        const vapidKey = 'BJr44Q87YwuvqcYpKTyV_fMt3lvtUSHtOr60R2U5vpnLHx8YZLf84m8DqQB_YNoRt_v1CuYHzbnyUt9-z99TzS4';
        
        try {
          token = await _messaging.getToken(vapidKey: vapidKey);
          _logger.i('Web FCM Token obtained: ${token?.substring(0, 20)}...');
        } catch (e) {
          _logger.w('Failed to get web FCM token: $e');
        }
      } else {
        try {
          token = await _messaging.getToken();
          _logger.i('Mobile FCM Token obtained: ${token?.substring(0, 20)}...');
        } catch (e) {
          _logger.w('Failed to get mobile FCM token: $e');
        }
      }
      
      if (token != null) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final notificationsEnabled = await areNotificationsEnabled();
          
          await _firestore.collection('Users').doc(user.uid).set({
            'fcmToken': token,
            'platform': kIsWeb ? 'web' : 'mobile',
            'notificationsEnabled': notificationsEnabled,
            'lastTokenUpdate': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }

      // Token refresh listener
      _messaging.onTokenRefresh.listen((newToken) async {
        _logger.i('FCM token refreshed');
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          try {
            await _firestore.collection('Users').doc(user.uid).update({
              'fcmToken': newToken,
              'platform': kIsWeb ? 'web' : 'mobile',
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
    }
  }

  Future<void> _setupNotificationListeners() async {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    
    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);

    // Handle notification taps
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
    _markNotificationAsRead(response.payload);
  }

  void _handleNotificationTap(RemoteMessage message) {
    _logger.i('FCM notification tapped: ${message.data}');
    resetNotificationCount();
    _markNotificationAsRead(message.data['notificationId']);
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    _logger.i('Foreground message: ${message.notification?.title}');
    
    final enabled = await areNotificationsEnabled();
    if (!enabled) return;
    
    await _incrementNotificationCount();
    
    if (kIsWeb) {
      await _showWebNotification(
        title: message.notification?.title ?? 'Maintenance Reminder',
        body: message.notification?.body ?? 'You have maintenance tasks to check',
        data: message.data,
      );
    } else {
      await _showLocalNotification(
        title: message.notification?.title ?? 'Maintenance Reminder',
        body: message.notification?.body ?? 'You have maintenance tasks to check',
        payload: message.data['notificationId'],
      );
    }
  }

  static Future<void> _handleBackgroundMessage(RemoteMessage message) async {
    Logger().i('Background message: ${message.notification?.title}');
    
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_notificationEnabledKey) ?? true;
    if (!enabled) return;
    
    final currentCount = prefs.getInt(_notificationCountKey) ?? 0;
    await prefs.setInt(_notificationCountKey, currentCount + 1);
  }

  Future<void> _showWebNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (!kIsWeb) return;
    _logger.i('Web notification triggered: $title');
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (kIsWeb) return;

    const androidDetails = AndroidNotificationDetails(
      'maintenance_channel',
      'Maintenance Notifications',
      channelDescription: 'Notifications for maintenance task reminders',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/launcher_icon',
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/launcher_icon'),
      color: Colors.blueGrey,
      enableVibration: true,
      playSound: true,
      enableLights: true,
      ledColor: Colors.blueGrey,
      ledOnMs: 1000,
      ledOffMs: 500,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.reminder,
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

  // Mark notification as read by specific user
  Future<void> markNotificationAsReadByUser(String notificationId, String userId) async {
    try {
      final notificationRef = _firestore.collection('Notifications').doc(notificationId);
      
      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(notificationRef);
        if (!doc.exists) return;
        
        final data = doc.data()!;
        final readByUsers = List<Map<String, dynamic>>.from(data['readByUsers'] ?? []);
        
        // Check if user already read this notification
        final existingIndex = readByUsers.indexWhere((r) => r['userId'] == userId);
        
        if (existingIndex == -1) {
          // Add new read info
          readByUsers.add({
            'userId': userId,
            'readAt': FieldValue.serverTimestamp(),
          });
          
          transaction.update(notificationRef, {
            'readByUsers': readByUsers,
            'isRead': readByUsers.isNotEmpty,
          });
        }
      });
      
      _logger.i('Notification $notificationId marked as read by user $userId');
    } catch (e) {
      _logger.e('Error marking notification as read by user: $e');
    }
  }

  // Mark notification as read (legacy method)
  Future<void> _markNotificationAsRead(String? notificationId) async {
    if (notificationId == null) return;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await markNotificationAsReadByUser(notificationId, user.uid);
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

  // Create grouped notification for multiple categories
  Future<String> createGroupedNotification({
    required List<CategoryInfo> categories,
    required DateTime lastInspectionDate,
    required List<String> assignedTechnicians,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Fixed null safety issues
      final frequencies = categories.map((c) => c.frequency).where((f) => f > 0).toList();
      if (frequencies.isEmpty) throw Exception('No valid frequencies found');
      
      final shortestFrequency = frequencies.reduce((a, b) => a < b ? a : b);

      final dates = calculateNotificationDates(
        lastInspectionDate: lastInspectionDate,
        frequencyMonths: shortestFrequency,
      );

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

      // Check for existing group on the same date
      final existingGroupQuery = await _firestore
          .collection('Notifications')
          .where('notificationDate', isEqualTo: Timestamp.fromDate(dates['notificationDate']!))
          .limit(1)
          .get();

      String notificationId;
      if (existingGroupQuery.docs.isNotEmpty) {
        final existingDoc = existingGroupQuery.docs.first;
        final existingGroup = GroupedNotificationModel.fromFirestore(existingDoc);
        
        final updatedNotifications = [...existingGroup.notifications, ...notifications];
        final updatedGroup = GroupedNotificationModel(
          id: existingDoc.id,
          notificationDate: existingGroup.notificationDate,
          notifications: updatedNotifications,
          isTriggered: false,
          isRead: false,
        );

        await existingDoc.reference.update(updatedGroup.toMap());
        notificationId = existingDoc.id;
      } else {
        final newGroup = GroupedNotificationModel(
          id: '',
          notificationDate: dates['notificationDate']!,
          notifications: notifications,
          isTriggered: false,
          isRead: false,
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

  // Stream methods for different notification views
  Stream<List<GroupedNotificationModel>> getAllNotifications() {
    return _firestore
        .collection('Notifications')
        .orderBy('notificationDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GroupedNotificationModel.fromFirestore(doc))
            .toList());
  }

  Stream<List<GroupedNotificationModel>> getUpcomingNotifications() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    return _firestore
        .collection('Notifications')
        .where('isTriggered', isEqualTo: false)
        .where('notificationDate', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
        .orderBy('notificationDate', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GroupedNotificationModel.fromFirestore(doc))
            .toList());
  }

  Stream<List<GroupedNotificationModel>> getSentNotifications() {
    return _firestore
        .collection('Notifications')
        .where('isTriggered', isEqualTo: true)
        .orderBy('triggeredAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GroupedNotificationModel.fromFirestore(doc))
            .toList());
  }

  Stream<List<GroupedNotificationModel>> getReceivedReadNotifications() {
    return _firestore
        .collection('Notifications')
        .where('isTriggered', isEqualTo: true)
        .orderBy('triggeredAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GroupedNotificationModel.fromFirestore(doc))
            .where((notification) => notification.readByUsers.isNotEmpty)
            .toList());
  }

  Stream<List<GroupedNotificationModel>> getPendingNotifications() {
    return _firestore
        .collection('Notifications')
        .where('isTriggered', isEqualTo: false)
        .orderBy('notificationDate', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GroupedNotificationModel.fromFirestore(doc))
            .toList());
  }

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

  Stream<List<GroupedNotificationModel>> getSetupNotifications() {
    return _firestore
        .collection('Notifications')
        .orderBy('notificationDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GroupedNotificationModel.fromFirestore(doc))
            .toList());
  }

  Stream<List<GroupedNotificationModel>> getTodaysTriggeredNotifications() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    return _firestore
        .collection('Notifications')
        .where('notificationDate', isEqualTo: Timestamp.fromDate(today))
        .where('isTriggered', isEqualTo: true)
        .orderBy('triggeredAt', descending: true)
        .limit(1)
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

      if (kIsWeb) {
        await _showWebNotification(
          title: title,
          body: body,
          data: {'test': 'true'},
        );
      } else {
        await _showLocalNotification(
          title: title,
          body: body,
        );
      }

      await _incrementNotificationCount();
      _logger.i('Test notification triggered');
    } catch (e) {
      _logger.e('Error sending test notification: $e');
    }
  }

  // Check for due notifications and trigger them
  Future<void> checkForDueNotifications() async {
    try {
      final now = DateTime.now();
      final currentHour = now.hour;
      
      // Only check at 9 AM and 11 AM
      if (currentHour != 9 && currentHour != 11) {
        return;
      }
      
      final today = DateTime(now.year, now.month, now.day);
      
      final dueNotificationsSnapshot = await _firestore
          .collection('Notifications')
          .where('notificationDate', isLessThanOrEqualTo: Timestamp.fromDate(today))
          .where('isTriggered', isEqualTo: false)
          .get();
      
      if (dueNotificationsSnapshot.docs.isNotEmpty) {
        _logger.i('Found ${dueNotificationsSnapshot.docs.length} due notifications');
        
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

  void dispose() {
    _periodicTimer?.cancel();
  }
}
