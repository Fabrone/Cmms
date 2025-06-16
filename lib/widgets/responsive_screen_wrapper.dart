import 'package:cmms/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'package:cmms/display%20screens/locations_screen.dart';
import 'package:cmms/display%20screens/building_survey_screen.dart';
import 'package:cmms/display%20screens/documentations_screen.dart';
import 'package:cmms/display%20screens/drawings_screen.dart';
import 'package:cmms/display%20screens/schedule_maintenance_screen.dart';
import 'package:cmms/technician/preventive_maintenance_screen.dart';
import 'package:cmms/display%20screens/reports_screen.dart';
import 'package:cmms/display%20screens/request_screen.dart';
import 'package:cmms/display%20screens/work_order_screen.dart';
import 'package:cmms/display%20screens/price_list_screen.dart';
import 'package:cmms/display%20screens/billing_screen.dart';
import 'package:cmms/display%20screens/equipment_supplied_screen.dart';
import 'package:cmms/display%20screens/inventory_screen.dart';
import 'package:cmms/display%20screens/vendor_screen.dart';
import 'package:cmms/display%20screens/kpi_screen.dart';
import 'package:cmms/display%20screens/report_screen.dart';
import 'package:cmms/screens/settings_screen.dart';
import 'package:cmms/screens/user_screen.dart';
import 'package:cmms/developer/developer_screen.dart';

class ResponsiveScreenWrapper extends StatefulWidget {
  final String title;
  final Widget child;
  final String facilityId;
  final String? currentRole;
  final String? organization;
  final bool isDeveloper;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final VoidCallback? onFacilityReset;

  const ResponsiveScreenWrapper({
    super.key,
    required this.title,
    required this.child,
    required this.facilityId,
    this.currentRole,
    this.organization,
    this.isDeveloper = false,
    this.actions,
    this.floatingActionButton,
    this.onFacilityReset,
  });

  @override
  State<ResponsiveScreenWrapper> createState() => _ResponsiveScreenWrapperState();
}

class _ResponsiveScreenWrapperState extends State<ResponsiveScreenWrapper> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _currentRole = 'User';
  String _organization = '-';

  @override
  void initState() {
    super.initState();
    _currentRole = widget.currentRole ?? 'User';
    _organization = widget.organization ?? '-';
    _getCurrentUserRole();
  }

  Future<void> _getCurrentUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final adminDoc = await FirebaseFirestore.instance.collection('Admins').doc(user.uid).get();
      final developerDoc = await FirebaseFirestore.instance.collection('Developers').doc(user.uid).get();
      final technicianDoc = await FirebaseFirestore.instance.collection('Technicians').doc(user.uid).get();
      final userDoc = await FirebaseFirestore.instance.collection('Users').doc(user.uid).get();

      String newRole = 'User';
      String newOrg = '-';

      if (adminDoc.exists) {
        newRole = 'Admin';
        final adminData = adminDoc.data();
        newOrg = adminData?['organization'] ?? '-';
      } else if (developerDoc.exists) {
        newRole = 'Technician';
        newOrg = 'JV Almacis';
      } else if (technicianDoc.exists) {
        newRole = 'Technician';
        final techData = technicianDoc.data();
        newOrg = techData?['organization'] ?? '-';
      } else if (userDoc.exists) {
        final userData = userDoc.data();
        if (userData != null && userData['role'] == 'Technician') {
          newRole = 'Technician';
          newOrg = '-';
        } else {
          newRole = 'User';
          newOrg = '-';
        }
      }

      if (mounted) {
        setState(() {
          _currentRole = newRole;
          _organization = newOrg;
        });
      }
    } catch (e) {
      _logger.e('Error getting user role: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: isMobile ? 18 : 20,
          ),
        ),
        backgroundColor: Colors.blueGrey[800],
        leading: isMobile
            ? IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
        actions: widget.actions,
        elevation: 0,
      ),
      drawer: isMobile ? _buildDrawer() : null,
      body: Row(
        children: [
          if (!isMobile) _buildSidebar(),
          Expanded(child: widget.child),
        ],
      ),
      floatingActionButton: widget.floatingActionButton,
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          _buildAppIcon(),
          Expanded(child: ListView(children: _buildMenuItems())),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 250,
      color: Colors.blueGrey[50],
      child: Column(
        children: [
          _buildAppIcon(),
          Expanded(
            child: ListView(
              children: _buildMenuItems(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppIcon() {
    return InkWell(
      onTap: widget.isDeveloper
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DeveloperScreen()),
              );
              if (MediaQuery.of(context).size.width <= 600) {
                Navigator.pop(context);
              }
              _logger.i('Developer navigated to DeveloperScreen');
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Image.asset(
          'assets/icons/icon.png',
          width: 60,
          height: 60,
        ),
      ),
    );
  }

  List<Widget> _buildMenuItems() {
    final role = _currentRole;
    final org = _organization;

    final Map<String, Map<String, List<String>>> roleMenuAccess = {
      'Admin': {
        'Embassy': [
          'Facilities', 'Locations', 'Building Survey', 'Drawings', 'Documentations',
          'Schedule Maintenance', 'Preventive Maintenance', 'Reports', 'Work on Request',
          'Work Orders', 'Billing', 'Report', 'Settings'
        ],
        'JV Almacis': [
          'Facilities', 'Locations', 'Building Survey', 'Drawings', 'Documentations',
          'Schedule Maintenance', 'Preventive Maintenance', 'Reports', 'Price Lists',
          'Work on Request', 'Work Orders', 'Equipment Supplied', 'Inventory and Parts',
          'Vendors', 'Users', 'KPIs', 'Billing', 'Report', 'Settings'
        ],
      },
      'Technician': {
        'Embassy': [
          'Facilities', 'Locations', 'Preventive Maintenance', 'Schedule Maintenance',
          'Building Survey', 'Drawings', 'Documentations', 'Reports', 'Work on Request',
          'Work Orders', 'Billing', 'Report', 'Settings'
        ],
        'JV Almacis': [
          'Facilities', 'Locations', 'Preventive Maintenance', 'Schedule Maintenance',
          'Building Survey', 'Drawings', 'Documentations', 'Reports', 'Price Lists',
          'Work on Request', 'Work Orders', 'Equipment Supplied', 'Inventory and Parts',
          'Billing', 'Report', 'Settings'
        ],
      },
      'User': {
        '-': [
          'Facilities', 'Settings'
        ],
      },
    };

    final menuStructure = [
      {'title': 'Facilities', 'icon': Icons.business, 'isSubItem': false},
      {'title': 'Locations', 'icon': Icons.location_on, 'isSubItem': false},
      {'title': 'Building Survey', 'icon': Icons.account_balance, 'isSubItem': false},
      {'title': 'Drawings', 'icon': Icons.brush, 'isSubItem': true},
      {'title': 'Documentations', 'icon': Icons.description, 'isSubItem': true},
      {'title': 'Schedule Maintenance', 'icon': Icons.event, 'isSubItem': false},
      {'title': 'Preventive Maintenance', 'icon': Icons.build_circle, 'isSubItem': true},
      {'title': 'Reports', 'icon': Icons.bar_chart, 'isSubItem': true},
      {'title': 'Work on Request', 'icon': Icons.request_page, 'isSubItem': false},
      {'title': 'Work Orders', 'icon': Icons.work, 'isSubItem': false},
      {'title': 'Price Lists', 'icon': Icons.attach_money, 'isSubItem': false},
      {'title': 'Billing', 'icon': Icons.receipt_long, 'isSubItem': false},
      {'title': 'Equipment Supplied', 'icon': Icons.construction, 'isSubItem': false},
      {'title': 'Inventory and Parts', 'icon': Icons.inventory, 'isSubItem': false},
      {'title': 'Vendors', 'icon': Icons.store, 'isSubItem': false},
      {'title': 'Users', 'icon': Icons.people, 'isSubItem': false},
      {'title': 'KPIs', 'icon': Icons.trending_up, 'isSubItem': false},
      {'title': 'Report', 'icon': Icons.bar_chart, 'isSubItem': false},
      {'title': 'Settings', 'icon': Icons.settings, 'isSubItem': false},
    ];

    final allowedItems = roleMenuAccess[role]?[org] ?? roleMenuAccess['User']!['-']!;
    final List<Widget> menuWidgets = [];

    for (var menuItem in menuStructure) {
      final itemTitle = menuItem['title'] as String;
      if (!allowedItems.contains(itemTitle)) {
        continue;
      }
      final icon = menuItem['icon'] as IconData;
      final isSubItem = menuItem['isSubItem'] as bool;

      menuWidgets.add(
        ListTile(
          contentPadding: isSubItem ? const EdgeInsets.only(left: 32.0, right: 16.0) : null,
          leading: Icon(icon, color: Colors.blueGrey),
          title: Text(itemTitle, style: GoogleFonts.poppins()),
          onTap: () => _handleMenuNavigation(itemTitle),
        ),
      );
    }

    return menuWidgets;
  }

  void _handleMenuNavigation(String title) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;
    if (isMobile) {
      Navigator.pop(context); // Close drawer
    }

    if (title == 'Facilities') {
      // Navigate to DashboardScreen for facility selection
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => const DashboardScreen(facilityId: '', role: 'User'),
        ),
        (route) => false, // Clear stack to prevent back navigation issues
      );
      _logger.i('Navigated to DashboardScreen for facility selection');
      return;
    }

    if (widget.facilityId.isEmpty && !['Settings'].contains(title)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select a facility first.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
      return;
    }

    final screenMap = {
      'Locations': () => LocationsScreen(facilityId: widget.facilityId),
      'Building Survey': () => BuildingSurveyScreen(facilityId: widget.facilityId, selectedSubSection: ''),
      'Documentations': () => DocumentationsScreen(facilityId: widget.facilityId),
      'Drawings': () => DrawingsScreen(facilityId: widget.facilityId),
      'Schedule Maintenance': () => ScheduleMaintenanceScreen(facilityId: widget.facilityId),
      'Preventive Maintenance': () => PreventiveMaintenanceScreen(facilityId: widget.facilityId),
      'Reports': () => ReportsScreen(facilityId: widget.facilityId),
      'Work on Request': () => RequestScreen(facilityId: widget.facilityId),
      'Work Orders': () => WorkOrderScreen(facilityId: widget.facilityId),
      'Price Lists': () => PriceListScreen(facilityId: widget.facilityId),
      'Billing': () => BillingScreen(facilityId: widget.facilityId, userRole: _currentRole),
      'Equipment Supplied': () => EquipmentSuppliedScreen(facilityId: widget.facilityId),
      'Inventory and Parts': () => InventoryScreen(facilityId: widget.facilityId),
      'Vendors': () => VendorScreen(facilityId: widget.facilityId),
      'Users': () => UserScreen(facilityId: widget.facilityId),
      'KPIs': () => KpiScreen(facilityId: widget.facilityId),
      'Report': () => ReportScreen(facilityId: widget.facilityId),
      'Settings': () => SettingsScreen(facilityId: widget.facilityId),
    };

    final screenBuilder = screenMap[title];
    if (screenBuilder != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => screenBuilder()),
      );
      _logger.i('Navigated to $title screen');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$title feature not found', style: GoogleFonts.poppins()),
        ),
      );
      _logger.w('Navigation failed: $title feature not found');
    }
  }
}