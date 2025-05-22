import 'package:cmms/authentication/login_screen.dart';
import 'package:cmms/authentication/registration_screen.dart';
import 'package:cmms/authentication/splaschscreen.dart';
import 'package:cmms/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';

// Background message handler (must be top-level)
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final logger = Logger();
  logger.i('Handling background message: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize notifications
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  const androidInitializationSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
  const initializationSettings = InitializationSettings(android: androidInitializationSettings);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Create Android notification channel
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'maintenance_reminders', // ID
    'Maintenance Reminders', // Name
    description: 'Notifications for scheduled and preventive maintenance tasks',
    importance: Importance.high,
  );
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // Set foreground notification options
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // Set up background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  final logger = Logger();
  try {
    await FirebaseFirestore.instance.clearPersistence();
    logger.i('Firestore cache cleared on app start');
  } catch (e, stackTrace) {
    logger.e('Error clearing Firestore cache: $e', stackTrace: stackTrace);
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const String defaultFacilityId = 'facility1'; // Default from logs

    return MaterialApp(
      title: 'Swedish Embassy Facility Management',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      home: const SplashScreen(),
      routes: {
        '/home': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as String?;
          return HomeScreen(facilityId: args ?? defaultFacilityId);
        },
        '/login': (context) => const LoginScreen(),
        '/registration': (context) => const RegistrationScreen(),
      },
    );
  }
}