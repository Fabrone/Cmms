import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/notification_model.dart';
import 'package:cmms/models/maintenance_task_model.dart';
import 'package:cmms/developer/notification_setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    // Create notification channel for Android
    const androidChannel = AndroidNotificationChannel(
      'maintenance_channel',
      'Maintenance Notifications',
      description: 'Notifications for maintenance task reminders',
      importance: Importance.high,
      playSound: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  Future<void> _initializeFCM() async {
    final token = await _messaging.getToken();
    _logger.i('FCM Token: $token');

    final user = FirebaseAuth.instance.currentUser;
    if (user != null && token != null) {
      await _firestore.collection('Users').doc(user.uid).set({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    _messaging.onTokenRefresh.listen((newToken) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _firestore.collection('Users').doc(user.uid).update({
          'fcmToken': newToken,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        });
      }
    });
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
    
    // Show local notification when app is in foreground
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
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
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

  // Get urgent notifications for widget display
  Stream<List<GroupedNotificationModel>> getUrgentNotifications() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    return _firestore
        .collection('Notifications')
        .where('notificationDate', isLessThanOrEqualTo: Timestamp.fromDate(today))
        .where('isTriggered', isEqualTo: true)
        .orderBy('notificationDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GroupedNotificationModel.fromFirestore(doc))
            .toList());
  }
}
