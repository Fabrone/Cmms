import 'dart:async';
import 'dart:io';
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
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:workmanager/workmanager.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Logger _logger = Logger();

  // Notification settings keys
  static const String _notificationCountKey = 'notification_count';
  static const String _notificationEnabledKey = 'notifications_enabled';
  static const String _autoNotificationEnabledKey = 'auto_notifications_enabled';
  static const String _defaultLastInspectionKey = 'default_last_inspection_date';
  static const String _soundEnabledKey = 'notification_sound_enabled';
  static const String _vibrationEnabledKey = 'notification_vibration_enabled';
  static const String _screenWakeEnabledKey = 'notification_screen_wake_enabled';

  // Timers and streams
  Timer? _periodicTimer;
  Timer? _automaticNotificationTimer;
  Timer? _alertTimer;
  Timer? _cleanupTimer;
  StreamSubscription? _notificationListener;

  // Initialize notification service
  Future<void> initialize() async {
    await _initializeLocalNotifications();
    await _initializeFCM();
    await _requestNotificationPermissions();
    await _setupNotificationListeners();
    await _initializeBackgroundTasks();
    
    // Start automatic notification processing
    await _startAutomaticNotificationProcessing();
    
    // Check for due notifications on startup
    await checkForDueNotifications();
    await checkForDueAlerts();
    
    // Set up periodic checks
    _periodicTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      checkForDueNotifications();
      checkForDueAlerts();
    });

    // Set up daily cleanup
    _cleanupTimer = Timer.periodic(const Duration(hours: 24), (_) {
      _cleanupExpiredNotifications();
    });
  }

  Future<void> _initializeBackgroundTasks() async {
    if (!kIsWeb && !Platform.isIOS) {
      await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
      await Workmanager().registerPeriodicTask(
        "notification-check",
        "checkDueNotifications",
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );
    }
  }

  // Settings methods with proper implementation
  Future<bool> areNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationEnabledKey) ?? true;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationEnabledKey, enabled);

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
      // Clean up automatic notifications
      await _cleanupAutomaticNotifications();
    }
  }

  Future<bool> isSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_soundEnabledKey) ?? true;
  }

  Future<void> setSoundEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundEnabledKey, enabled);
  }

  Future<bool> isVibrationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_vibrationEnabledKey) ?? true;
  }

  Future<void> setVibrationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_vibrationEnabledKey, enabled);
  }

  Future<bool> isScreenWakeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_screenWakeEnabledKey) ?? true;
  }

  Future<void> setScreenWakeEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_screenWakeEnabledKey, enabled);
  }

  Future<DateTime> getDefaultLastInspectionDate() async {
    final prefs = await SharedPreferences.getInstance();
    final dateString = prefs.getString(_defaultLastInspectionKey);
    if (dateString != null) {
      return DateTime.parse(dateString);
    }
    return DateTime(DateTime.now().year, 1, 1);
  }

  Future<void> setDefaultLastInspectionDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultLastInspectionKey, date.toIso8601String());
  }

  // Enhanced notification permissions
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

  // Enhanced local notifications initialization
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

    // Create notification channels
    await _createNotificationChannels();
  }

  Future<void> _createNotificationChannels() async {
    if (kIsWeb) return;

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      // Normal notifications channel
      const normalChannel = AndroidNotificationChannel(
        'maintenance_normal',
        'Maintenance Notifications',
        description: 'Regular maintenance task reminders',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        ledColor: Colors.blueGrey,
      );

      // Urgent notifications channel
      const urgentChannel = AndroidNotificationChannel(
        'maintenance_urgent',
        'Urgent Maintenance Alerts',
        description: 'Urgent maintenance alerts requiring immediate attention',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        ledColor: Colors.red,
        enableLights: true,
      );

      // Critical notifications channel
      const criticalChannel = AndroidNotificationChannel(
        'maintenance_critical',
        'Critical Maintenance Alerts',
        description: 'Critical maintenance alerts',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        ledColor: Colors.red,
        enableLights: true,
      );

      await androidPlugin.createNotificationChannel(normalChannel);
      await androidPlugin.createNotificationChannel(urgentChannel);
      await androidPlugin.createNotificationChannel(criticalChannel);
    }
  }

  // Enhanced FCM initialization
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

  // Enhanced notification listeners
  Future<void> _setupNotificationListeners() async {
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
    
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

    final priority = NotificationPriority.values.firstWhere(
      (e) => e.name == message.data['priority'],
      orElse: () => NotificationPriority.normal,
    );

    if (kIsWeb) {
      await _showWebNotification(
        title: message.notification?.title ?? 'Maintenance Reminder',
        body: message.notification?.body ?? 'You have maintenance tasks to check',
        data: message.data,
        priority: priority,
      );
    } else {
      await _showLocalNotification(
        title: message.notification?.title ?? 'Maintenance Reminder',
        body: message.notification?.body ?? 'You have maintenance tasks to check',
        payload: message.data['notificationId'],
        priority: priority,
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

  // Enhanced notification display with sound and vibration
  Future<void> _showWebNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
    NotificationPriority priority = NotificationPriority.normal,
  }) async {
    if (!kIsWeb) return;
    
    await _playNotificationSound(priority);
    _logger.i('Web notification triggered: $title');
    
    // Web notifications would be handled by the browser
    // The floating widget will show the actual notification
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
    NotificationPriority priority = NotificationPriority.normal,
  }) async {
    if (kIsWeb) return;

    final soundEnabled = await isSoundEnabled();
    final vibrationEnabled = await isVibrationEnabled();
    final screenWakeEnabled = await isScreenWakeEnabled();

    String channelId;
    switch (priority) {
      case NotificationPriority.critical:
        channelId = 'maintenance_critical';
        break;
      case NotificationPriority.urgent:
        channelId = 'maintenance_urgent';
        break;
      default:
        channelId = 'maintenance_normal';
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      priority == NotificationPriority.critical ? 'Critical Maintenance Alerts' :
      priority == NotificationPriority.urgent ? 'Urgent Maintenance Alerts' :
      'Maintenance Notifications',
      channelDescription: 'Maintenance task reminders and alerts',
      importance: priority == NotificationPriority.critical ? Importance.max :
                 priority == NotificationPriority.urgent ? Importance.high :
                 Importance.defaultImportance,
      priority: priority == NotificationPriority.critical ? Priority.max :
               priority == NotificationPriority.urgent ? Priority.high :
               Priority.defaultPriority,
      showWhen: true,
      icon: '@mipmap/launcher_icon',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/launcher_icon'),
      color: priority == NotificationPriority.critical ? Colors.red :
             priority == NotificationPriority.urgent ? Colors.orange :
             Colors.blueGrey,
      enableVibration: vibrationEnabled,
      playSound: soundEnabled,
      enableLights: true,
      ledColor: priority == NotificationPriority.critical ? Colors.red :
                priority == NotificationPriority.urgent ? Colors.orange :
                Colors.blueGrey,
      ledOnMs: 1000,
      ledOffMs: 500,
      fullScreenIntent: screenWakeEnabled && priority != NotificationPriority.normal,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      autoCancel: false,
      ongoing: priority == NotificationPriority.critical,
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

    // Play sound and vibration
    if (soundEnabled) {
      await _playNotificationSound(priority);
    }
    
    if (vibrationEnabled && !kIsWeb) {
      await _triggerVibration(priority);
    }
  }

  // Sound implementation
  Future<void> _playNotificationSound(NotificationPriority priority) async {
    try {
      String soundFile;
      switch (priority) {
        case NotificationPriority.critical:
          soundFile = 'sounds/critical_alert.wav';
          break;
        case NotificationPriority.urgent:
          soundFile = 'sounds/urgent_alert.wav';
          break;
        default:
          soundFile = 'sounds/maintenance_notification.wav';
      }
      
      await _audioPlayer.play(AssetSource(soundFile));
    } catch (e) {
      _logger.e('Error playing notification sound: $e');
      // Fallback to system sound
      try {
        await _audioPlayer.play(AssetSource('sounds/default_notification.mp3'));
      } catch (e2) {
        _logger.e('Error playing fallback sound: $e2');
      }
    }
  }

  // Vibration implementation
  Future<void> _triggerVibration(NotificationPriority priority) async {
    try {
      if (await Vibration.hasVibrator()) {
        switch (priority) {
          case NotificationPriority.critical:
            await Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 500]);
            break;
          case NotificationPriority.urgent:
            await Vibration.vibrate(pattern: [0, 300, 100, 300]);
            break;
          default:
            await Vibration.vibrate(duration: 200);
        }
      }
    } catch (e) {
      _logger.e('Error triggering vibration: $e');
    }
  }

  // Enhanced notification count management
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

  // Enhanced read status tracking with user names
  Future<void> markNotificationAsReadByUser(String notificationId, String userId) async {
    try {
      // Get user name
      String userName = 'Unknown User';
      try {
        final userDoc = await _firestore.collection('Users').doc(userId).get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          userName = userData['name'] ?? userData['email'] ?? 'Unknown User';
        }
      } catch (e) {
        _logger.w('Could not fetch user name for $userId: $e');
      }

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
            'userName': userName,
            'readAt': FieldValue.serverTimestamp(),
          });

          transaction.update(notificationRef, {
            'readByUsers': readByUsers,
            'isRead': readByUsers.isNotEmpty,
          });
        }
      });

      _logger.i('Notification $notificationId marked as read by user $userName ($userId)');
    } catch (e) {
      _logger.e('Error marking notification as read by user: $e');
    }
  }

  Future<void> _markNotificationAsRead(String? notificationId) async {
    if (notificationId == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await markNotificationAsReadByUser(notificationId, user.uid);
    }
  }

  // Enhanced date calculations with leap year handling
  Map<String, DateTime> calculateNotificationDates({
    required DateTime lastInspectionDate,
    required int frequencyMonths,
  }) {
    // Calculate next inspection date considering leap years
    DateTime nextInspectionDate = DateTime(
      lastInspectionDate.year,
      lastInspectionDate.month + frequencyMonths,
      lastInspectionDate.day,
    );

    // Handle month overflow
    while (nextInspectionDate.month > 12) {
      nextInspectionDate = DateTime(
        nextInspectionDate.year + 1,
        nextInspectionDate.month - 12,
        nextInspectionDate.day,
      );
    }

    // Handle day overflow for months with different day counts
    final daysInMonth = DateTime(nextInspectionDate.year, nextInspectionDate.month + 1, 0).day;
    if (nextInspectionDate.day > daysInMonth) {
      nextInspectionDate = DateTime(
        nextInspectionDate.year,
        nextInspectionDate.month,
        daysInMonth,
      );
    }

    // Notification date: 5 days before next inspection
    final notificationDate = nextInspectionDate.subtract(const Duration(days: 5));
    
    // Alert date: 1 day before next inspection
    final alertDate = nextInspectionDate.subtract(const Duration(days: 1));

    return {
      'nextInspectionDate': nextInspectionDate,
      'notificationDate': notificationDate,
      'alertDate': alertDate,
    };
  }

  // Enhanced notification creation with alerts
  Future<String> createFrequencyBasedNotification({
    required List<MaintenanceTaskModel> tasks,
    required DateTime lastInspectionDate,
    required List<String> assignedUsers,
    NotificationType type = NotificationType.custom,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Group tasks by their notification date
      final Map<DateTime, List<NotificationModel>> groupedByDate = {};
      final Map<DateTime, List<NotificationModel>> groupedAlertsByDate = {};

      for (final task in tasks) {
        final dates = calculateNotificationDates(
          lastInspectionDate: lastInspectionDate,
          frequencyMonths: task.frequency,
        );

        // Create notification
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
          alertDate: dates['alertDate']!,
          assignedTechnicians: assignedUsers,
          createdAt: DateTime.now(),
          createdBy: user.uid,
          type: type,
          priority: NotificationPriority.normal,
          alertType: AlertType.notification,
          isAlert: false,
        );

        // Create alert
        final alert = NotificationModel(
          id: '',
          taskId: '',
          category: task.category,
          component: task.component,
          intervention: task.intervention,
          frequency: task.frequency,
          lastInspectionDate: lastInspectionDate,
          nextInspectionDate: dates['nextInspectionDate']!,
          notificationDate: dates['alertDate']!, // Alert uses alert date as notification date
          alertDate: dates['alertDate']!,
          assignedTechnicians: assignedUsers,
          createdAt: DateTime.now(),
          createdBy: user.uid,
          type: type,
          priority: NotificationPriority.urgent,
          alertType: AlertType.alert,
          isAlert: true,
        );

        final notificationDateKey = DateTime(
          dates['notificationDate']!.year,
          dates['notificationDate']!.month,
          dates['notificationDate']!.day,
        );

        final alertDateKey = DateTime(
          dates['alertDate']!.year,
          dates['alertDate']!.month,
          dates['alertDate']!.day,
        );

        if (!groupedByDate.containsKey(notificationDateKey)) {
          groupedByDate[notificationDateKey] = [];
        }
        groupedByDate[notificationDateKey]!.add(notification);

        if (!groupedAlertsByDate.containsKey(alertDateKey)) {
          groupedAlertsByDate[alertDateKey] = [];
        }
        groupedAlertsByDate[alertDateKey]!.add(alert);
      }

      final List<String> createdNotificationIds = [];

      // Create grouped notifications
      for (final entry in groupedByDate.entries) {
        final notificationDate = entry.key;
        final notifications = entry.value;

        // Calculate expiry date for custom notifications (2 days after next inspection)
        DateTime? expiryDate;
        if (type == NotificationType.custom) {
          final latestNextInspection = notifications
              .map((n) => n.nextInspectionDate)
              .reduce((a, b) => a.isAfter(b) ? a : b);
          expiryDate = latestNextInspection.add(const Duration(days: 2));
        }

        final newGroup = GroupedNotificationModel(
          id: '',
          notificationDate: notificationDate,
          notifications: notifications,
          alerts: [], // Alerts will be added separately
          isTriggered: false,
          isRead: false,
          type: type,
          priority: NotificationPriority.normal,
          expiryDate: expiryDate,
        );

        final docRef = await _firestore.collection('Notifications').add(newGroup.toMap());
        createdNotificationIds.add(docRef.id);
      }

      // Create grouped alerts
      for (final entry in groupedAlertsByDate.entries) {
        final alertDate = entry.key;
        final alerts = entry.value;

        // Calculate expiry date for custom alerts
        DateTime? expiryDate;
        if (type == NotificationType.custom) {
          final latestNextInspection = alerts
              .map((a) => a.nextInspectionDate)
              .reduce((a, b) => a.isAfter(b) ? a : b);
          expiryDate = latestNextInspection.add(const Duration(days: 2));
        }

        final newAlertGroup = GroupedNotificationModel(
          id: '',
          notificationDate: alertDate,
          notifications: [], // No notifications in alert group
          alerts: alerts,
          isTriggered: false,
          isRead: false,
          type: type,
          priority: NotificationPriority.urgent,
          expiryDate: expiryDate,
        );

        final docRef = await _firestore.collection('Notifications').add(newAlertGroup.toMap());
        createdNotificationIds.add(docRef.id);
      }

      return createdNotificationIds.first;
    } catch (e) {
      _logger.e('Error creating frequency-based notification: $e');
      rethrow;
    }
  }

  // Enhanced automatic notifications with proper cycling
  Future<void> _generateAutomaticNotifications() async {
    try {
      final defaultDate = await getDefaultLastInspectionDate();
      final allUsers = await getAllUserIds();

      if (allUsers.isEmpty) {
        _logger.w('No users found for automatic notifications');
        return;
      }

      // Clean up existing automatic notifications first
      await _cleanupAutomaticNotifications();

      final tasksSnapshot = await _firestore.collection('Maintenance_Tasks').get();
      final tasks = tasksSnapshot.docs
          .map((doc) => MaintenanceTaskModel.fromFirestore(doc))
          .toList();

      if (tasks.isNotEmpty) {
        await createFrequencyBasedNotification(
          tasks: tasks,
          lastInspectionDate: defaultDate,
          assignedUsers: allUsers,
          type: NotificationType.automatic,
        );

        _logger.i('Automatic notifications generated for ${tasks.length} tasks');
      }
    } catch (e) {
      _logger.e('Error generating automatic notifications: $e');
    }
  }

  Future<void> _cleanupAutomaticNotifications() async {
    try {
      final automaticNotifications = await _firestore
          .collection('Notifications')
          .where('type', isEqualTo: 'automatic')
          .get();

      for (final doc in automaticNotifications.docs) {
        await doc.reference.delete();
      }

      _logger.i('Cleaned up ${automaticNotifications.docs.length} automatic notifications');
    } catch (e) {
      _logger.e('Error cleaning up automatic notifications: $e');
    }
  }

  // Enhanced automatic notification processing with proper cycling
  Future<void> _startAutomaticNotificationProcessing() async {
    final enabled = await areAutoNotificationsEnabled();
    if (!enabled) return;

    // Set up daily check for automatic notification cycling
    _automaticNotificationTimer = Timer.periodic(const Duration(hours: 24), (_) async {
      await _cycleAutomaticNotifications();
    });

    // Initial check
    await _cycleAutomaticNotifications();
  }

  Future<void> _cycleAutomaticNotifications() async {
    try {
      final enabled = await areAutoNotificationsEnabled();
      if (!enabled) return;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Find automatic notifications that have passed their next inspection date
      final expiredNotifications = await _firestore
          .collection('Notifications')
          .where('type', isEqualTo: 'automatic')
          .get();

      for (final doc in expiredNotifications.docs) {
        final notification = GroupedNotificationModel.fromFirestore(doc);
        
        // Check if any task in this notification has passed its next inspection date
        bool needsCycling = false;
        for (final task in notification.allItems) {
          final nextInspectionDate = DateTime(
            task.nextInspectionDate.year,
            task.nextInspectionDate.month,
            task.nextInspectionDate.day,
          );
          
          if (today.isAfter(nextInspectionDate)) {
            needsCycling = true;
            break;
          }
        }

        if (needsCycling) {
          await _cycleNotificationTasks(notification);
          await doc.reference.delete(); // Remove old notification
        }
      }
    } catch (e) {
      _logger.e('Error cycling automatic notifications: $e');
    }
  }

  Future<void> _cycleNotificationTasks(GroupedNotificationModel notification) async {
    try {
      final allUsers = await getAllUserIds();

      for (final task in notification.allItems) {
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
          alertDate: dates['alertDate']!,
          assignedTechnicians: allUsers,
          createdAt: DateTime.now(),
          createdBy: 'system',
          type: NotificationType.automatic,
          priority: task.isAlert ? NotificationPriority.urgent : NotificationPriority.normal,
          alertType: task.alertType,
          isAlert: task.isAlert,
        );

        await _createOrUpdateGroupedNotification(newNotification);
      }

      _logger.i('Cycled ${notification.allItems.length} notification tasks');
    } catch (e) {
      _logger.e('Error cycling notification tasks: $e');
    }
  }

  Future<void> _createOrUpdateGroupedNotification(NotificationModel notification) async {
    final notificationDate = notification.notificationDate;
    final dateKey = DateTime(notificationDate.year, notificationDate.month, notificationDate.day);

    final existingQuery = await _firestore
        .collection('Notifications')
        .where('notificationDate', isEqualTo: Timestamp.fromDate(dateKey))
        .where('isTriggered', isEqualTo: false)
        .where('type', isEqualTo: notification.type.name)
        .limit(1)
        .get();

    if (existingQuery.docs.isNotEmpty) {
      // Update existing group
      final existingDoc = existingQuery.docs.first;
      final existingGroup = GroupedNotificationModel.fromFirestore(existingDoc);

      List<NotificationModel> updatedNotifications = [...existingGroup.notifications];
      List<NotificationModel> updatedAlerts = [...existingGroup.alerts];

      if (notification.isAlert) {
        updatedAlerts.add(notification);
      } else {
        updatedNotifications.add(notification);
      }

      final updatedGroup = GroupedNotificationModel(
        id: existingDoc.id,
        notificationDate: existingGroup.notificationDate,
        notifications: updatedNotifications,
        alerts: updatedAlerts,
        isTriggered: false,
        isRead: false,
        type: notification.type,
        priority: existingGroup.priority,
      );

      await existingDoc.reference.update(updatedGroup.toMap());
    } else {
      // Create new group
      final newGroup = GroupedNotificationModel(
        id: '',
        notificationDate: dateKey,
        notifications: notification.isAlert ? [] : [notification],
        alerts: notification.isAlert ? [notification] : [],
        isTriggered: false,
        isRead: false,
        type: notification.type,
        priority: notification.priority,
      );

      await _firestore.collection('Notifications').add(newGroup.toMap());
    }
  }

  // Enhanced due notification checking with retry logic
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
        _logger.i('Found ${dueNotificationsSnapshot.docs.length} due notifications');

        for (final doc in dueNotificationsSnapshot.docs) {
          final notification = GroupedNotificationModel.fromFirestore(doc);
          
          // Check if notification needs retry
          if (notification.needsRetry) {
            await _triggerNotification(doc);
          }
        }
      }
    } catch (e) {
      _logger.e('Error checking for due notifications: $e');
    }
  }

  // New method for checking due alerts
  Future<void> checkForDueAlerts() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final dueAlertsSnapshot = await _firestore
          .collection('Notifications')
          .where('notificationDate', isLessThanOrEqualTo: Timestamp.fromDate(today))
          .where('isTriggered', isEqualTo: false)
          .where('priority', isEqualTo: 'urgent')
          .get();

      if (dueAlertsSnapshot.docs.isNotEmpty) {
        _logger.i('Found ${dueAlertsSnapshot.docs.length} due alerts');

        for (final doc in dueAlertsSnapshot.docs) {
          await _triggerNotification(doc, isAlert: true);
        }
      }
    } catch (e) {
      _logger.e('Error checking for due alerts: $e');
    }
  }

  // Enhanced notification triggering with retry logic
  Future<void> _triggerNotification(DocumentSnapshot doc, {bool isAlert = false}) async {
    try {
      final notification = GroupedNotificationModel.fromFirestore(doc);
      final items = isAlert ? notification.alerts : notification.notifications;
      final categories = items.map((n) => n.category).toSet().toList();

      final title = isAlert ? 'Maintenance Alert - Due Tomorrow!' : 'Maintenance Tasks Due';
      final body = isAlert 
          ? '${items.length} maintenance tasks are due tomorrow - immediate attention required!'
          : '${items.length} tasks in ${categories.length} categories need attention';

      final priority = isAlert ? NotificationPriority.urgent : NotificationPriority.normal;

      // Get all users for sending notifications
      final allUsers = await getAllUserIds();

      // Send notifications to all users
      for (final userId in allUsers) {
        await _sendNotificationToUser(userId, title, body, doc.id, priority);
      }

      // Update notification as triggered with retry count
      await doc.reference.update({
        'isTriggered': true,
        'triggeredAt': FieldValue.serverTimestamp(),
        'retryCount': notification.retryCount + 1,
        'lastRetryAt': FieldValue.serverTimestamp(),
      });

      _logger.i('${isAlert ? "Alert" : "Notification"} triggered: ${doc.id}');
    } catch (e) {
      _logger.e('Error triggering notification: $e');
      
      // Update retry count even on failure
      try {
        final notification = GroupedNotificationModel.fromFirestore(doc);
        await doc.reference.update({
          'retryCount': notification.retryCount + 1,
          'lastRetryAt': FieldValue.serverTimestamp(),
        });
      } catch (e2) {
        _logger.e('Error updating retry count: $e2');
      }
    }
  }

  Future<void> _sendNotificationToUser(
    String userId, 
    String title, 
    String body, 
    String notificationId,
    NotificationPriority priority,
  ) async {
    try {
      final userDoc = await _firestore.collection('Users').doc(userId).get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;
        final notificationsEnabled = userData['notificationsEnabled'] as bool? ?? true;

        if (notificationsEnabled) {
          await _showLocalNotification(
            title: title,
            body: body,
            payload: notificationId,
            priority: priority,
          );
        }
      }
    } catch (e) {
      _logger.e('Error sending notification to user $userId: $e');
    }
  }

  // Cleanup expired notifications
  Future<void> _cleanupExpiredNotifications() async {
    try {
      final now = DateTime.now();
      
      final expiredNotifications = await _firestore
          .collection('Notifications')
          .where('type', isEqualTo: 'custom')
          .where('expiryDate', isLessThan: Timestamp.fromDate(now))
          .get();

      for (final doc in expiredNotifications.docs) {
        await doc.reference.delete();
      }

      if (expiredNotifications.docs.isNotEmpty) {
        _logger.i('Cleaned up ${expiredNotifications.docs.length} expired notifications');
      }
    } catch (e) {
      _logger.e('Error cleaning up expired notifications: $e');
    }
  }

  // Get all user IDs
  Future<List<String>> getAllUserIds() async {
    try {
      final List<String> userIds = [];

      final collections = ['Users', 'Admins', 'Technicians', 'Developers'];

      for (final collection in collections) {
        final snapshot = await _firestore.collection(collection).get();
        userIds.addAll(snapshot.docs.map((doc) => doc.id));
      }

      return userIds.toSet().toList();
    } catch (e) {
      _logger.e('Error getting user IDs: $e');
      return [];
    }
  }

  // Enhanced test notification with agent mode
  Future<void> triggerTestNotification({
    String? targetAudience = 'both',
    String? customTitle,
    String? customBody,
    bool isAgentMode = false,
  }) async {
    try {
      final title = customTitle ?? (isAgentMode ? 'Agent Notification' : 'Test Maintenance Reminder');
      final body = customBody ?? (isAgentMode ? 'Custom agent message' : 'This is a test notification for maintenance tasks.');

      final testNotification = {
        'title': title,
        'body': body,
        'isTest': !isAgentMode,
        'isAgent': isAgentMode,
        'targetAudience': targetAudience,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
      };

      final docRef = await _firestore.collection('TestNotifications').add(testNotification);

      // Send notification immediately
      if (kIsWeb) {
        await _showWebNotification(
          title: title,
          body: body,
          data: {'test': 'true', 'testId': docRef.id},
          priority: NotificationPriority.normal,
        );
      } else {
        await _showLocalNotification(
          title: title,
          body: body,
          payload: docRef.id,
          priority: NotificationPriority.normal,
        );
      }

      await _incrementNotificationCount();
      _logger.i('${isAgentMode ? "Agent" : "Test"} notification triggered with ID: ${docRef.id}');
    } catch (e) {
      _logger.e('Error sending ${isAgentMode ? "agent" : "test"} notification: $e');
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

  // Enhanced stream methods
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
    final tomorrow = today.add(const Duration(days: 1));

    return _firestore
        .collection('Notifications')
        .where('notificationDate', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
        .where('notificationDate', isLessThan: Timestamp.fromDate(tomorrow))
        .where('isTriggered', isEqualTo: true)
        .orderBy('notificationDate', descending: false)
        .orderBy('triggeredAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GroupedNotificationModel.fromFirestore(doc))
            .toList());
  }

  Stream<List<GroupedNotificationModel>> getActiveNotifications() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return _firestore
        .collection('Notifications')
        .where('notificationDate', isLessThanOrEqualTo: Timestamp.fromDate(today))
        .where('isTriggered', isEqualTo: true)
        .orderBy('notificationDate', descending: false)
        .orderBy('triggeredAt', descending: true)
        .limit(5)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GroupedNotificationModel.fromFirestore(doc))
            .toList());
  }

  void dispose() {
    _periodicTimer?.cancel();
    _automaticNotificationTimer?.cancel();
    _alertTimer?.cancel();
    _cleanupTimer?.cancel();
    _notificationListener?.cancel();
    _audioPlayer.dispose();
  }
}

// Background task callback
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case "checkDueNotifications":
        try {
          final notificationService = NotificationService();
          await notificationService.checkForDueNotifications();
          await notificationService.checkForDueAlerts();
          return Future.value(true);
        } catch (e) {
          Logger().e('Background task error: $e');
          return Future.value(false);
        }
      default:
        return Future.value(false);
    }
  });
}
