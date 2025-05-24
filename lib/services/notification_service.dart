import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/notification_model.dart';
import 'package:cmms/models/maintenance_task_model.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final Logger _logger = Logger();

  // Initialize notification service
  Future<void> initialize() async {
    await _initializeLocalNotifications();
    await _initializeFCM();
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
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
  }

  Future<void> _initializeFCM() async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Get FCM token for this device
    final token = await _messaging.getToken();
    _logger.i('FCM Token: $token');

    // Save token to user document
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _firestore.collection('Users').doc(user.uid).update({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      });
    }

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    
    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);
  }

  void _onNotificationTapped(NotificationResponse response) {
    _logger.i('Notification tapped: ${response.payload}');
    // Handle notification tap - navigate to appropriate screen
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    _logger.i('Foreground message: ${message.notification?.title}');
    
    // Show local notification when app is in foreground
    await _showLocalNotification(
      title: message.notification?.title ?? 'Maintenance Reminder',
      body: message.notification?.body ?? 'You have maintenance tasks to check',
      payload: message.data['payload'],
    );
  }

  static Future<void> _handleBackgroundMessage(RemoteMessage message) async {
    Logger().i('Background message: ${message.notification?.title}');
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
    );

    const iosDetails = DarwinNotificationDetails();
    
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

      if (existingGroupQuery.docs.isNotEmpty) {
        // Add to existing group
        final existingDoc = existingGroupQuery.docs.first;
        final existingGroup = GroupedNotificationModel.fromFirestore(existingDoc);
        
        final updatedNotifications = [...existingGroup.notifications, notification];
        final updatedGroup = GroupedNotificationModel(
          notificationDate: existingGroup.notificationDate,
          notifications: updatedNotifications,
          isTriggered: existingGroup.isTriggered,
        );

        await existingDoc.reference.update(updatedGroup.toMap());
        return existingDoc.id;
      } else {
        // Create new group
        final newGroup = GroupedNotificationModel(
          notificationDate: dates['notificationDate']!,
          notifications: [notification],
        );

        final docRef = await _firestore.collection('Notifications').add(newGroup.toMap());
        return docRef.id;
      }
    } catch (e) {
      _logger.e('Error creating notification: $e');
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

  // Send notification to technicians
  Future<void> sendNotificationToTechnicians({
    required List<String> technicianIds,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      for (final technicianId in technicianIds) {
        // Get technician's FCM token
        final userDoc = await _firestore.collection('Users').doc(technicianId).get();
        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          final fcmToken = userData['fcmToken'] as String?;
          final email = userData['email'] as String?;

          if (fcmToken != null) {
            // Send FCM notification
            await _sendFCMNotification(
              token: fcmToken,
              title: title,
              body: body,
              data: data,
            );
          }

          if (email != null) {
            // Send email notification
            await _sendEmailNotification(
              email: email,
              title: title,
              body: body,
            );
          }
        }
      }
    } catch (e) {
      _logger.e('Error sending notifications to technicians: $e');
    }
  }

  Future<void> _sendFCMNotification({
    required String token,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    // This would typically use Firebase Admin SDK or a cloud function
    // For now, we'll log the notification
    _logger.i('Sending FCM notification to token: $token');
    _logger.i('Title: $title, Body: $body');
  }

  Future<void> _sendEmailNotification({
    required String email,
    required String title,
    required String body,
  }) async {
    try {
      // Store email notification request in Firestore for cloud function to process
      await _firestore.collection('EmailNotifications').add({
        'to': email,
        'subject': title,
        'body': body,
        'timestamp': FieldValue.serverTimestamp(),
        'processed': false,
      });
      
      _logger.i('Email notification queued for: $email');
    } catch (e) {
      _logger.e('Error queuing email notification: $e');
    }
  }

  // Check and trigger due notifications
  Future<void> checkAndTriggerNotifications() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final dueNotificationsQuery = await _firestore
          .collection('Notifications')
          .where('notificationDate', isLessThanOrEqualTo: Timestamp.fromDate(today))
          .where('isTriggered', isEqualTo: false)
          .get();

      for (final doc in dueNotificationsQuery.docs) {
        final groupedNotification = GroupedNotificationModel.fromFirestore(doc);
        
        // Create notification message
        final categories = groupedNotification.notifications.map((n) => n.category).toSet().toList();
        const title = 'Maintenance Reminder';
        final body = 'You have ${groupedNotification.notifications.length} maintenance tasks due in categories: ${categories.join(', ')}';

        // Get all technician IDs
        final technicianIds = await getTechnicianIds();

        // Send notifications
        await sendNotificationToTechnicians(
          technicianIds: technicianIds,
          title: title,
          body: body,
          data: {
            'notificationId': doc.id,
            'type': 'maintenance_reminder',
            'taskCount': groupedNotification.notifications.length.toString(),
          },
        );

        // Mark as triggered
        await doc.reference.update({'isTriggered': true});
        
        _logger.i('Triggered notification for ${groupedNotification.notifications.length} tasks');
      }
    } catch (e) {
      _logger.e('Error checking and triggering notifications: $e');
    }
  }

  // Get pending notifications for a user
  Stream<List<GroupedNotificationModel>> getPendingNotifications() {
    return _firestore
        .collection('Notifications')
        .where('isTriggered', isEqualTo: true)
        .where('isCompleted', isEqualTo: false)
        .orderBy('notificationDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GroupedNotificationModel.fromFirestore(doc))
            .toList());
  }
}
