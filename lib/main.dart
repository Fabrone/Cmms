import 'package:cmms/authentication/login_screen.dart';
import 'package:cmms/authentication/registration_screen.dart';
import 'package:cmms/authentication/splaschscreen.dart';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/screens/home_screen.dart';
import 'package:cmms/screens/facility_screen.dart';
import 'package:cmms/screens/work_order_screen.dart';
import 'package:cmms/screens/price_list_screen.dart';
import 'package:cmms/screens/drawings_screen.dart';
import 'package:cmms/screens/documentations_screen.dart';
import 'package:cmms/screens/equipment_supplied_screen.dart';
import 'package:cmms/screens/inventory_screen.dart';
import 'package:cmms/screens/request_screen.dart';
import 'package:cmms/screens/preventive_maintenance_screen.dart';
import 'package:cmms/screens/building_survey_screen.dart';
import 'package:cmms/screens/schedule_maintenance_screen.dart';
import 'package:cmms/screens/location_screen.dart';
import 'package:cmms/screens/user_screen.dart';
import 'package:cmms/screens/report_screen.dart';
import 'package:cmms/screens/reports_screen.dart';
import 'package:cmms/screens/kpi_screen.dart';
import 'package:cmms/screens/vendor_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
        '/facilities': (context) => const FacilityScreen(
              facilityId: defaultFacilityId,
            ),
        '/work_orders': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as String?;
          return WorkOrderScreen(facilityId: args ?? defaultFacilityId);
        },
        '/price_list': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as String?;
          return PriceListScreen(facilityId: args ?? defaultFacilityId);
        },
        '/drawings': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as String?;
          return DrawingsScreen(facilityId: args ?? defaultFacilityId);
        },
        '/equipment_supplied': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as String?;
          return EquipmentSuppliedScreen(facilityId: args ?? defaultFacilityId);
        },
        '/inventory': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as String?;
          return InventoryScreen(facilityId: args ?? defaultFacilityId);
        },
        '/requests': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as String?;
          return RequestScreen(facilityId: args ?? defaultFacilityId);
        },
        '/preventive_maintenance': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as String?;
          return PreventiveMaintenanceScreen(facilityId: args ?? defaultFacilityId);
        },
        '/documentations': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as String?;
          return DocumentationsScreen(facilityId: args ?? defaultFacilityId);
        },
        '/building_survey': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as String?;
          return BuildingSurveyScreen(
            facilityId: args ?? defaultFacilityId,
            selectedSubSection: 'building_survey',
          );
        },
        '/schedule_maintenance': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as String?;
          return ScheduleMaintenanceScreen(
            facilityId: args ?? defaultFacilityId,
            selectedSubSection: 'schedule_maintenance',
          );
        },
        '/locations': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as String?;
          return LocationScreen(facilityId: args ?? defaultFacilityId);
        },
        '/users': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as String?;
          return UserScreen(facilityId: args ?? defaultFacilityId);
        },
        '/vendors': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as String?;
          return VendorScreen(facilityId: args ?? defaultFacilityId);
        },
        '/reports': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as String?;
          return ReportScreen(facilityId: args ?? defaultFacilityId);
        },
        '/scheduled_reports': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as String?;
          return ReportsScreen(facilityId: args ?? defaultFacilityId);
        },
        '/kpis': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as String?;
          return KpiScreen(facilityId: args ?? defaultFacilityId);
        },
        '/pdf_viewer': (context) => const Placeholder(),
        '/login': (context) => const LoginScreen(),
        '/registration': (context) => const RegistrationScreen(),
      },
    );
  }
}