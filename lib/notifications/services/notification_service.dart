import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import 'package:cmms/notifications/models/notification_model.dart';
import 'package:cmms/notifications/models/maintenance_task_model.dart';
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
  static const String _autoNotificationEnabledKey = 'auto_notifications_enabled';
  static const String _defaultLastInspectionKey = 'default_last_inspection_date';
  
  // Timers for automatic processing
  Timer? _periodicTimer;
  Timer? _automaticNotificationTimer;
  StreamSubscription? _notificationListener;
  
  // Initialize notification service
  Future<void> initialize() async {
    await _initializeLocalNotifications();
    await _initializeFCM();
    await _requestNotificationPermissions();
    await _setupNotificationListeners();
    
    // Start automatic notification processing
    await _startAutomaticNotificationProcessing();
    
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
      await _localNotifications.cancelAll();
      await resetNotificationCount();
    }
  }

  Future<bool> areAutoNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoNotificationEnabledKey) ?? false;
  }

  Future<void> setAutoNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoNotificationEnabledKey, enabled);
    
    if (enabled) {
      await _generateAutomaticNotifications();
      await _startAutomaticNotificationProcessing();
    } else {
      _automaticNotificationTimer?.cancel();
    }
  }

  Future<DateTime> getDefaultLastInspectionDate() async {
    final prefs = await SharedPreferences.getInstance();
    final dateString = prefs.getString(_defaultLastInspectionKey);
    if (dateString != null) {
      return DateTime.parse(dateString);
    }
    // Default to January 1st of current year
    return DateTime(DateTime.now().year, 1, 1);
  }

  Future<void> setDefaultLastInspectionDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultLastInspectionKey, date.toIso8601String());
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
        isUrgent: true,
      );
    }
  }

  static Future<void> _handleBackgroundMessage(RemoteMessage message) async {
    Logger().i('Background message: ${message.notification?.title}');
    
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('notifications_enabled') ?? true;
    if (!enabled) return;
    
    final currentCount = prefs.getInt('notification_count') ?? 0;
    await prefs.setInt('notification_count', currentCount + 1);
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
    bool isUrgent = false,
  }) async {
    if (kIsWeb) return;

    final androidDetails = AndroidNotificationDetails(
      'maintenance_channel',
      'Maintenance Notifications',
      channelDescription: 'Notifications for maintenance task reminders',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/launcher_icon',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/launcher_icon'),
      color: Colors.blueGrey,
      enableVibration: true,
      playSound: true,
      enableLights: true,
      ledColor: Colors.blueGrey,
      ledOnMs: 1000,
      ledOffMs: 500,
      fullScreenIntent: isUrgent, // Wake screen for urgent notifications
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      autoCancel: false, // Keep in status bar until tapped
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
      interruptionLevel: InterruptionLevel.timeSensitive,
    );
    
    final details = NotificationDetails(
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

  // Create grouped notification for multiple tasks based on frequency
  Future<String> createFrequencyBasedNotification({
    required List<MaintenanceTaskModel> tasks,
    required DateTime lastInspectionDate,
    required List<String> assignedUsers,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Group tasks by their notification date (based on frequency)
      final Map<DateTime, List<NotificationModel>> groupedByDate = {};
      
      for (final task in tasks) {
        final dates = calculateNotificationDates(
          lastInspectionDate: lastInspectionDate,
          frequencyMonths: task.frequency,
        );

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
          assignedTechnicians: assignedUsers,
          createdAt: DateTime.now(),
          createdBy: user.uid,
        );

        final notificationDate = dates['notificationDate']!;
        final dateKey = DateTime(notificationDate.year, notificationDate.month, notificationDate.day);
        
        if (!groupedByDate.containsKey(dateKey)) {
          groupedByDate[dateKey] = [];
        }
        groupedByDate[dateKey]!.add(notification);
      }

      // Create grouped notifications for each date
      final List<String> createdNotificationIds = [];
      
      for (final entry in groupedByDate.entries) {
        final notificationDate = entry.key;
        final notifications = entry.value;

        // Check for existing group on the same date
        final existingGroupQuery = await _firestore
            .collection('Notifications')
            .where('notificationDate', isEqualTo: Timestamp.fromDate(notificationDate))
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
            notificationDate: notificationDate,
            notifications: notifications,
            isTriggered: false,
            isRead: false,
          );

          final docRef = await _firestore.collection('Notifications').add(newGroup.toMap());
          notificationId = docRef.id;
        }
        
        createdNotificationIds.add(notificationId);
      }

      return createdNotificationIds.first; // Return first created notification ID
    } catch (e) {
      _logger.e('Error creating frequency-based notification: $e');
      rethrow;
    }
  }

  // Get all user IDs (not just technicians)
  Future<List<String>> getAllUserIds() async {
    try {
      final List<String> userIds = [];
      
      // Get from all user collections
      final collections = ['Users', 'Admins', 'Technicians', 'Developers'];
      
      for (final collection in collections) {
        final snapshot = await _firestore.collection(collection).get();
        userIds.addAll(snapshot.docs.map((doc) => doc.id));
      }
      
      return userIds.toSet().toList(); // Remove duplicates
    } catch (e) {
      _logger.e('Error getting user IDs: $e');
      return [];
    }
  }

  // Generate automatic notifications for all maintenance tasks
  Future<void> _generateAutomaticNotifications() async {
    try {
      final defaultDate = await getDefaultLastInspectionDate();
      final allUsers = await getAllUserIds();
      
      if (allUsers.isEmpty) {
        _logger.w('No users found for automatic notifications');
        return;
      }

      final tasksSnapshot = await _firestore.collection('Maintenance_Tasks').get();
      final tasks = tasksSnapshot.docs
          .map((doc) => MaintenanceTaskModel.fromFirestore(doc))
          .toList();

      if (tasks.isNotEmpty) {
        await createFrequencyBasedNotification(
          tasks: tasks,
          lastInspectionDate: defaultDate,
          assignedUsers: allUsers,
        );
        
        _logger.i('Automatic notifications generated for ${tasks.length} tasks');
      }
    } catch (e) {
      _logger.e('Error generating automatic notifications: $e');
    }
  }

  // Start automatic notification processing
  Future<void> _startAutomaticNotificationProcessing() async {
    final enabled = await areAutoNotificationsEnabled();
    if (!enabled) return;

    // Listen for notification updates and handle automatic cycling
    _notificationListener = _firestore
        .collection('Notifications')
        .where('isTriggered', isEqualTo: true)
        .snapshots()
        .listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified) {
          await _handleTriggeredNotification(change.doc);
        }
      }
    });

    // Set up daily check for automatic notification cycling
    _automaticNotificationTimer = Timer.periodic(const Duration(hours: 24), (_) async {
      await _cycleCompletedNotifications();
    });
  }

  // Handle triggered notification for automatic cycling
  Future<void> _handleTriggeredNotification(DocumentSnapshot doc) async {
    try {
      final notification = GroupedNotificationModel.fromFirestore(doc);
      final now = DateTime.now();
      
      // Check if notification was triggered and the next day has passed
      if (notification.isTriggered && 
          notification.triggeredAt != null &&
          now.isAfter(notification.triggeredAt!.add(const Duration(days: 1)))) {
        
        await _cycleNotificationTasks(notification);
      }
    } catch (e) {
      _logger.e('Error handling triggered notification: $e');
    }
  }

  // Cycle notification tasks to create new notifications
  Future<void> _cycleNotificationTasks(GroupedNotificationModel notification) async {
    try {
      final allUsers = await getAllUserIds();
      
      for (final task in notification.notifications) {
        // Use the next inspection date as the new last inspection date
        final newLastInspectionDate = task.nextInspectionDate;
        
        final dates = calculateNotificationDates(
          lastInspectionDate: newLastInspectionDate,
          frequencyMonths: task.frequency,
        );

        final newNotification = NotificationModel(
          id: '',
          taskId: task.taskId,
          category: task.category,
          component: task.component,
          intervention: task.intervention,
          frequency: task.frequency,
          lastInspectionDate: newLastInspectionDate,
          nextInspectionDate: dates['nextInspectionDate']!,
          notificationDate: dates['notificationDate']!,
          assignedTechnicians: allUsers,
          createdAt: DateTime.now(),
          createdBy: 'system',
        );

        // Create new grouped notification for the new date
        await _createOrUpdateGroupedNotification(newNotification);
        
        // Update the maintenance task with new dates
        await _updateMaintenanceTaskDates(task, newLastInspectionDate, dates['nextInspectionDate']!);
      }
      
      _logger.i('Cycled ${notification.notifications.length} notification tasks');
    } catch (e) {
      _logger.e('Error cycling notification tasks: $e');
    }
  }

  // Create or update grouped notification
  Future<void> _createOrUpdateGroupedNotification(NotificationModel notification) async {
    final notificationDate = notification.notificationDate;
    final dateKey = DateTime(notificationDate.year, notificationDate.month, notificationDate.day);
    
    final existingQuery = await _firestore
        .collection('Notifications')
        .where('notificationDate', isEqualTo: Timestamp.fromDate(dateKey))
        .where('isTriggered', isEqualTo: false)
        .limit(1)
        .get();

    if (existingQuery.docs.isNotEmpty) {
      // Update existing group
      final existingDoc = existingQuery.docs.first;
      final existingGroup = GroupedNotificationModel.fromFirestore(existingDoc);
      
      final updatedNotifications = [...existingGroup.notifications, notification];
      final updatedGroup = GroupedNotificationModel(
        id: existingDoc.id,
        notificationDate: existingGroup.notificationDate,
        notifications: updatedNotifications,
        isTriggered: false,
        isRead: false,
      );

      await existingDoc.reference.update(updatedGroup.toMap());
    } else {
      // Create new group
      final newGroup = GroupedNotificationModel(
        id: '',
        notificationDate: dateKey,
        notifications: [notification],
        isTriggered: false,
        isRead: false,
      );

      await _firestore.collection('Notifications').add(newGroup.toMap());
    }
  }

  // Update maintenance task dates
  Future<void> _updateMaintenanceTaskDates(
    NotificationModel task,
    DateTime newLastInspectionDate,
    DateTime newNextInspectionDate,
  ) async {
    try {
      // Find the maintenance task document
      final tasksQuery = await _firestore
          .collection('Maintenance_Tasks')
          .where('category', isEqualTo: task.category)
          .where('component', isEqualTo: task.component)
          .where('intervention', isEqualTo: task.intervention)
          .limit(1)
          .get();

      if (tasksQuery.docs.isNotEmpty) {
        final taskDoc = tasksQuery.docs.first;
        await taskDoc.reference.update({
          'lastInspectionDate': Timestamp.fromDate(newLastInspectionDate),
          'nextInspectionDate': Timestamp.fromDate(newNextInspectionDate),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      _logger.e('Error updating maintenance task dates: $e');
    }
  }

  // Cycle completed notifications (daily check)
  Future<void> _cycleCompletedNotifications() async {
    try {
      final enabled = await areAutoNotificationsEnabled();
      if (!enabled) return;

      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      
      final completedNotificationsQuery = await _firestore
          .collection('Notifications')
          .where('isTriggered', isEqualTo: true)
          .where('triggeredAt', isLessThan: Timestamp.fromDate(yesterday))
          .get();

      for (final doc in completedNotificationsQuery.docs) {
        final notification = GroupedNotificationModel.fromFirestore(doc);
        await _cycleNotificationTasks(notification);
      }
      
      _logger.i('Cycled ${completedNotificationsQuery.docs.length} completed notifications');
    } catch (e) {
      _logger.e('Error cycling completed notifications: $e');
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
  Future<void> triggerTestNotification({
    String? targetAudience = 'both', // 'technicians', 'admins', 'both'
  }) async {
    try {
      const title = 'Test Maintenance Reminder';
      const body = 'This is a test notification for maintenance tasks.';

      // Create test notification document
      final testNotification = {
        'title': title,
        'body': body,
        'isTest': true,
        'targetAudience': targetAudience,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
      };

      final docRef = await _firestore.collection('TestNotifications').add(testNotification);

      // Send to devices
      if (kIsWeb) {
        await _showWebNotification(
          title: title,
          body: body,
          data: {'test': 'true', 'testId': docRef.id},
        );
      } else {
        await _showLocalNotification(
          title: title,
          body: body,
          payload: docRef.id,
          isUrgent: true,
        );
      }

      await _incrementNotificationCount();
      _logger.i('Test notification triggered with ID: ${docRef.id}');
    } catch (e) {
      _logger.e('Error sending test notification: $e');
      rethrow;
    }
  }

  // Delete test notification
  Future<void> deleteTestNotification(String testNotificationId) async {
    try {
      await _firestore.collection('TestNotifications').doc(testNotificationId).delete();
      _logger.i('Test notification deleted: $testNotificationId');
    } catch (e) {
      _logger.e('Error deleting test notification: $e');
      rethrow;
    }
  }

  // Get test notifications
  Stream<List<Map<String, dynamic>>> getTestNotifications() {
    return _firestore
        .collection('TestNotifications')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList());
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
        
        for (final doc in dueNotificationsSnapshot.docs) {
          await _triggerNotification(doc);
        }
      }
    } catch (e) {
      _logger.e('Error checking for due notifications: $e');
    }
  }

  // Trigger individual notification
  Future<void> _triggerNotification(DocumentSnapshot doc) async {
    try {
      final notification = GroupedNotificationModel.fromFirestore(doc);
      final categories = notification.notifications.map((n) => n.category).toSet().toList();
      
      const title = 'Maintenance Tasks Due';
      final body = '${notification.notifications.length} tasks in ${categories.length} categories need attention';
      
      // Get all users for sending notifications
      final allUsers = await getAllUserIds();
      
      // Send FCM notifications to all users
      for (final userId in allUsers) {
        await _sendFCMNotificationToUser(userId, title, body, doc.id);
      }
      
      // Update notification as triggered
      await doc.reference.update({
        'isTriggered': true,
        'triggeredAt': FieldValue.serverTimestamp(),
      });
      
      _logger.i('Notification triggered: ${doc.id}');
    } catch (e) {
      _logger.e('Error triggering notification: $e');
    }
  }

  // Send FCM notification to specific user
  Future<void> _sendFCMNotificationToUser(String userId, String title, String body, String notificationId) async {
    try {
      final userDoc = await _firestore.collection('Users').doc(userId).get();
      
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        final fcmToken = userData['fcmToken'] as String?;
        final notificationsEnabled = userData['notificationsEnabled'] as bool? ?? true;
        
        if (fcmToken != null && notificationsEnabled) {
          // For now, we'll use local notifications since we're avoiding cloud functions
          // In a production environment, you would send FCM messages here
          await _showLocalNotification(
            title: title,
            body: body,
            payload: notificationId,
            isUrgent: true,
          );
        }
      }
    } catch (e) {
      _logger.e('Error sending FCM notification to user $userId: $e');
    }
  }

  void dispose() {
    _periodicTimer?.cancel();
    _automaticNotificationTimer?.cancel();
    _notificationListener?.cancel();
  }
}
