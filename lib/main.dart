import 'package:cmms/authentication/login_screen.dart';
import 'package:cmms/authentication/registration_screen.dart';
import 'package:cmms/authentication/splaschscreen.dart';
import 'package:cmms/developer/maintenance_tasks_screen.dart';
import 'package:cmms/notifications/screens/notification_settings_screen.dart';
import 'package:cmms/notifications/screens/notification_status_screen.dart';
import 'package:cmms/screens/dashboard_screen.dart';
import 'package:cmms/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'firebase_options.dart';

// Background message handler (must be top-level)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // Check if notifications are enabled
  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool('notifications_enabled') ?? true;
  if (!enabled) return;
  
  // Increment notification count for background messages
  final currentCount = prefs.getInt('notification_count') ?? 0;
  await prefs.setInt('notification_count', currentCount + 1);
  
  final logger = Logger();
  logger.i('Handling background message: ${message.messageId}');
}

// Initialize the notification channel for Android
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'maintenance_channel',
  'Maintenance Notifications',
  description: 'Notifications for maintenance task reminders',
  importance: Importance.high,
  playSound: true,
  enableVibration: true,
  ledColor: Colors.blueGrey,
);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final logger = Logger();
  
  // Clear Firestore persistence before any Firestore operations
  try {
    await FirebaseFirestore.instance.clearPersistence();
    logger.i('Firestore cache cleared on app start');
  } catch (e, stackTrace) {
    logger.e('Error clearing Firestore cache: $e', stackTrace: stackTrace);
  }

  // Set up background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize local notifications (mobile only)
  if (!kIsWeb) {
    const androidInitializationSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    const iosInitializationSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initializationSettings = InitializationSettings(
      android: androidInitializationSettings,
      iOS: iosInitializationSettings,
    );
    
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        logger.i('Local notification tapped: ${response.payload}');
        NotificationService().resetNotificationCount();
      },
    );

    // Create Android notification channel
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Set foreground notification options
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  // Initialize the notification service
  try {
    await NotificationService().initialize();
    logger.i('Notification service initialized successfully');
  } catch (e) {
    logger.e('Error initializing notification service: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final Logger _logger = Logger();

  @override
  void initState() {
    super.initState();
    _setupForegroundMessageHandling();
  }

  void _setupForegroundMessageHandling() {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      _logger.i('Received foreground message: ${message.notification?.title}');
      
      // Check if notifications are enabled
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('notifications_enabled') ?? true;
      if (!enabled) return;
      
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;
      
      // Increment notification count
      await NotificationService().incrementNotificationCount();
      
      if (kIsWeb) {
        // Web notifications are handled by the service worker
        _logger.i('Web notification will be handled by service worker');
      } else {
        // Mobile notifications
        if (notification != null && android != null) {
          flutterLocalNotificationsPlugin.show(
            notification.hashCode,
            notification.title,
            notification.body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                channel.id,
                channel.name,
                channelDescription: channel.description,
                icon: '@mipmap/launcher_icon',
                importance: Importance.max,
                priority: Priority.high,
                playSound: true,
                enableVibration: true,
                enableLights: true,
                ledColor: Colors.blueGrey,
                fullScreenIntent: true, // For screen wake
                category: AndroidNotificationCategory.reminder,
                styleInformation: const BigTextStyleInformation(''),
              ),
            ),
            payload: message.data['notificationId'],
          );
        }
      }
    });
    
    // Handle notification taps when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _logger.i('Notification opened app: ${message.notification?.title}');
      NotificationService().resetNotificationCount();
      
      // Navigate to maintenance tasks screen
      navigatorKey.currentState?.pushNamed('/maintenance-tasks');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NyumbaSmart',
      navigatorKey: navigatorKey,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: GoogleFonts.poppinsTextTheme(),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.light,
        ),
      ),
      home: const SplashScreen(),
      routes: {
        '/home': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as String?;
          return DashboardScreen(facilityId: args ?? '', role: '');
        },
        '/login': (context) => const LoginScreen(),
        '/registration': (context) => const RegistrationScreen(),
        '/maintenance-tasks': (context) => const MaintenanceTasksScreen(), 
        '/notification-status': (context) => const NotificationStatusScreen(),
        '/notification-settings': (context) => const NotificationSettingsScreen(),
      },
    );
  }
}