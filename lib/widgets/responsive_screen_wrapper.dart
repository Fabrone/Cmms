import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

class ResponsiveScreenWrapper extends StatelessWidget {
  final String title;
  final Widget child;
  final String facilityId;
  final String? currentRole;
  final String? organization;
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
    this.actions,
    this.floatingActionButton,
    this.onFacilityReset,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;
    final isTabletOrWeb = screenWidth > 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: isMobile ? 20 : 24,
          ),
        ),
        backgroundColor: Colors.blueGrey[800],
        leading: isMobile
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        actions: actions,
        elevation: 0,
      ),
      body: Row(
        children: [
          // Sidebar for tablet/web
          if (isTabletOrWeb) _buildSidebar(context),
          // Main content
          Expanded(child: child),
        ],
      ),
      floatingActionButton: floatingActionButton,
    );
  }

  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: 250,
      color: Colors.blueGrey[50],
      child: Column(
        children: [
          _buildAppIcon(),
          Expanded(
            child: ListView(
              children: _buildMenuItems(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppIcon() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Image.asset(
        'assets/icons/icon.png',
        width: 60,
        height: 60,
      ),
    );
  }

  List<Widget> _buildMenuItems(BuildContext context) {
    final role = currentRole ?? 'User';
    final org = organization ?? '-';
    
    // Role-specific menu access
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
          'Facilities', 'Locations', 'Schedule Maintenance', 'Preventive Maintenance',
          'Reports', 'Price Lists', 'Work on Request', 'Work Orders', 'Equipment Supplied',
          'Inventory and Parts', 'Billing', 'Settings'
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
      {'title': 'KPIs', 'icon': Icons.trending_up, 'isSubItem': false},
      {'title': 'Report', 'icon': Icons.bar_chart, 'isSubItem': false},
      {'title': 'Settings', 'icon': Icons.settings, 'isSubItem': false},
    ];

    final allowedItems = roleMenuAccess[role]?[org] ?? roleMenuAccess['User']!['-']!;
    final List<Widget> menuWidgets = [];
    
    for (var menuItem in menuStructure) {
      final itemTitle = menuItem['title'] as String;
      
      // Skip items not allowed for this role/organization
      if (!allowedItems.contains(itemTitle)) {
        continue;
      }
      
      final icon = menuItem['icon'] as IconData;
      final isSubItem = menuItem['isSubItem'] as bool;
      
      // Special handling for "Facilities" item
      if (itemTitle == 'Facilities') {
        menuWidgets.add(
          ListTile(
            leading: Icon(icon, color: Colors.blueGrey),
            title: Text(itemTitle, style: GoogleFonts.poppins()),
            onTap: () {
              if (onFacilityReset != null) {
                onFacilityReset!();
              } else {
                Navigator.pop(context);
              }
            },
          ),
        );
        continue;
      }
      
      menuWidgets.add(
        ListTile(
          contentPadding: isSubItem 
              ? const EdgeInsets.only(left: 32.0, right: 16.0)
              : null,
          leading: Icon(icon, color: Colors.blueGrey),
          title: Text(itemTitle, style: GoogleFonts.poppins()),
          onTap: () => _handleMenuNavigation(context, itemTitle),
        ),
      );
    }
    
    return menuWidgets;
  }

  void _handleMenuNavigation(BuildContext context, String title) {
    if (facilityId.isEmpty) {
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
      'Locations': () => LocationsScreen(facilityId: facilityId),
      'Building Survey': () => BuildingSurveyScreen(facilityId: facilityId, selectedSubSection: ''),
      'Documentations': () => DocumentationsScreen(facilityId: facilityId),
      'Drawings': () => DrawingsScreen(facilityId: facilityId),
      'Schedule Maintenance': () => ScheduleMaintenanceScreen(facilityId: facilityId),
      'Preventive Maintenance': () => PreventiveMaintenanceScreen(facilityId: facilityId),
      'Reports': () => ReportsScreen(facilityId: facilityId),
      'Work on Request': () => RequestScreen(facilityId: facilityId),
      'Work Orders': () => WorkOrderScreen(facilityId: facilityId),
      'Price Lists': () => PriceListScreen(facilityId: facilityId),
      'Billing': () => BillingScreen(facilityId: facilityId, userRole: currentRole ?? 'User'),
      'Equipment Supplied': () => EquipmentSuppliedScreen(facilityId: facilityId),
      'Inventory and Parts': () => InventoryScreen(facilityId: facilityId),
      'Vendors': () => VendorScreen(facilityId: facilityId),
      'Users': () => UserScreen(facilityId: facilityId),
      'KPIs': () => KpiScreen(facilityId: facilityId),
      'Report': () => ReportScreen(facilityId: facilityId),
      'Settings': () => SettingsScreen(facilityId: facilityId),
    };

    final screenBuilder = screenMap[title];
    if (screenBuilder != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => screenBuilder()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$title feature not found', style: GoogleFonts.poppins()),
        ),
      );
    }
  }
}
