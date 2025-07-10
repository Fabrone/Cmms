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
import 'package:cmms/developer/developer_screen.dart';
import 'dart:async';

class ResponsiveScreenWrapper extends StatefulWidget {
  final String title;
  final Widget child;
  final String facilityId;
  final String? currentRole;
  final String? organization;
  final String? selectedOrganizationName;
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
    this.selectedOrganizationName,
    this.actions,
    this.floatingActionButton,
    this.onFacilityReset,
  });

  @override
  State<ResponsiveScreenWrapper> createState() =>
      _ResponsiveScreenWrapperState();
}

class _ResponsiveScreenWrapperState extends State<ResponsiveScreenWrapper> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _currentRole = 'User';
  String _organization = '-';
  final bool _isDeveloper = false;
  bool _isClient = false;
  
  // Static variable to persist expansion state across widget rebuilds
  static bool _isBuildingInfoExpanded = false;
  
  final List<StreamSubscription<DocumentSnapshot>> _organizationSubscriptions = [];

  @override
  void initState() {
    super.initState();
    _currentRole = widget.currentRole ?? 'User';
    _organization = widget.organization ?? '-';
    _logger.i(
        'Initializing ResponsiveScreenWrapper for ${widget.title}, facilityId: ${widget.facilityId}, role: $_currentRole, org: $_organization, selectedOrg: ${widget.selectedOrganizationName}');
    _fetchUserRoleWithRetry();
    _setupOrganizationListeners();
    
    // Force rebuild after 2 seconds to catch late query results
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {});
        _logger.d('Forced UI rebuild for ${widget.title} after 2s');
      }
    });
  }

  @override
  void dispose() {
    for (var subscription in _organizationSubscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _setupOrganizationListeners() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Clear existing subscriptions
    for (var subscription in _organizationSubscriptions) {
      subscription.cancel();
    }
    _organizationSubscriptions.clear();

    // Listen to Users collection for organization changes
    final usersStream = FirebaseFirestore.instance
        .collection('Users')
        .doc(user.uid)
        .snapshots();
    
    final usersSubscription = usersStream.listen(
      (snapshot) {
        if (snapshot.exists) {
          _logger.i('Organization update detected in Users collection for ${user.uid}');
          _checkClientStatus();
        }
      },
      onError: (error) {
        _logger.e('Error in Users organization listener: $error');
      },
    );
    _organizationSubscriptions.add(usersSubscription);

    // Listen to Technicians collection for organization changes
    final techniciansStream = FirebaseFirestore.instance
        .collection('Technicians')
        .doc(user.uid)
        .snapshots();
    
    final techniciansSubscription = techniciansStream.listen(
      (snapshot) {
        if (snapshot.exists) {
          _logger.i('Organization update detected in Technicians collection for ${user.uid}');
          _checkClientStatus();
        }
      },
      onError: (error) {
        _logger.e('Error in Technicians organization listener: $error');
      },
    );
    _organizationSubscriptions.add(techniciansSubscription);
  }

  Future<void> _checkClientStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      bool isClient = false;
      String orgFromCheck = '-';

      // First check if user is a Technician
      final technicianDoc = await FirebaseFirestore.instance
          .collection('Technicians')
          .doc(user.uid)
          .get();

      if (technicianDoc.exists) {
        orgFromCheck = technicianDoc.data()?['organization'] ?? '-';
        isClient = orgFromCheck != 'JV Almacis';
        _logger.i('Technician organization check: $orgFromCheck, isClient: $isClient');
      } else {
        // User is not a Technician - check organization from Users collection
        final userDoc = await FirebaseFirestore.instance
            .collection('Users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          orgFromCheck = userDoc.data()?['organization'] ?? '-';
          isClient = orgFromCheck != 'JV Almacis';
          _logger.i('User organization check: $orgFromCheck, isClient: $isClient');
        }
      }

      if (mounted) {
        setState(() {
          _isClient = isClient;
          _organization = orgFromCheck;
        });
        _logger.i('Updated client status: isClient=$isClient, org=$orgFromCheck');
      }
    } catch (e) {
      _logger.e('Error checking client status: $e');
    }
  }

  Future<void> _fetchUserRoleWithRetry({int retries = 3, int delayMs = 500}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _logger.w('No user logged in, skipping role fetch for ${widget.title}');
      if (mounted) {
        setState(() {});
      }
      return;
    }

    _logger.i(
        'Fetching role for user: ${user.uid} on ${widget.title}, facilityId: ${widget.facilityId}, retries left: $retries');
    for (int attempt = 1; attempt <= retries; attempt++) {
      try {
        final adminDoc = await FirebaseFirestore.instance
            .collection('Admins')
            .doc(user.uid)
            .get();
        final developerDoc = await FirebaseFirestore.instance
            .collection('Developers')
            .doc(user.uid)
            .get();
        final technicianDoc = await FirebaseFirestore.instance
            .collection('Technicians')
            .doc(user.uid)
            .get();
        final userDoc = await FirebaseFirestore.instance
            .collection('Users')
            .doc(user.uid)
            .get();

        _logger.d(
            'Firestore results for ${widget.title}: Admin=${adminDoc.exists}, Developer=${developerDoc.exists}, Technician=${technicianDoc.exists}, User=${userDoc.exists}');

        String newRole = 'User';
        String newOrg = '-';

        if (adminDoc.exists) {
          newRole = 'Admin';
          final adminData = adminDoc.data();
          newOrg = adminData?['organization'] ?? '-';
          _logger.i('User is Admin, org: $newOrg');
        } else if (developerDoc.exists) {
          newRole = 'Technician';
          newOrg = 'JV Almacis';
          _logger.i('User is Developer (displayed as Technician), org: $newOrg');
        } else if (technicianDoc.exists) {
          newRole = 'Technician';
          final techData = technicianDoc.data();
          newOrg = techData?['organization'] ?? '-';
          _logger.i('User is Technician, org: $newOrg');
        } else if (userDoc.exists) {
          final userData = userDoc.data();
          newRole = userData?['role'] ?? 'User';
          newOrg = userData?['organization'] ?? '-';
          _logger.i('User is ${userData?['role'] ?? 'User'}, org: $newOrg');
        }

        if (mounted) {
          setState(() {
            _currentRole = newRole;
            _organization = newOrg;
          });
        }

        await _checkClientStatus();
        return;
      } catch (e, stackTrace) {
        _logger.e(
            'Error getting user role and organization on attempt $attempt: $e',
            stackTrace: stackTrace);
        if (attempt < retries) {
          await Future.delayed(Duration(milliseconds: delayMs));
          delayMs *= 2;
        } else {
          if (mounted) {
            setState(() {});
          }
          _logger.e(
              'Failed to fetch user role and organization after $retries attempts');
        }
      }
    }
  }

  void _handleDeveloperIconTap() async {
    if (!_isDeveloper) {
      _logger.w('App icon tapped but user is not a developer');
      return;
    }

    _logger.i('App icon clicked, navigating to DeveloperScreen');

    try {
      final screenWidth = MediaQuery.of(context).size.width;
      final isMobile = screenWidth <= 600;

      if (isMobile && _scaffoldKey.currentState?.isDrawerOpen == true) {
        Navigator.pop(context);
        _logger.i('Closed drawer before navigation');
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const DeveloperScreen()),
        );
        _logger.i('Successfully navigated to DeveloperScreen');
      }
    } catch (e) {
      _logger.e('Error navigating to DeveloperScreen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening developer screen: $e',
                style: GoogleFonts.poppins()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;
    final String appBarTitle = _organization == '-' ? 'Dashboard' : widget.title;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(
          appBarTitle,
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
    _logger.d('Building drawer for ${widget.title}, isDeveloper: $_isDeveloper, isClient: $_isClient, selectedOrg: ${widget.selectedOrganizationName}');
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
    _logger.d('Building sidebar for ${widget.title}, isDeveloper: $_isDeveloper, isClient: $_isClient, selectedOrg: ${widget.selectedOrganizationName}');
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
    _logger.d('Building app icon for ${widget.title}, isDeveloper: $_isDeveloper, isClient: $_isClient, selectedOrg: ${widget.selectedOrganizationName}');

    return GestureDetector(
      onTap: _isDeveloper ? _handleDeveloperIconTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        width: double.infinity,
        child: Center(
          child: Column(
            children: [
              Stack(
                children: [
                  Container(
                    decoration: _isDeveloper
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.blueGrey.withValues(alpha: 0.1),
                          )
                        : null,
                    padding: const EdgeInsets.all(8),
                    child: Image.asset(
                      'assets/icons/icon.png',
                      width: 60,
                      height: 60,
                    ),
                  ),
                  if (_isClient && _organization != 'JV Almacis')
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Client',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (!_isClient && widget.selectedOrganizationName != null && widget.selectedOrganizationName!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Managing: ${widget.selectedOrganizationName}',
                    style: GoogleFonts.poppins(
                      color: Colors.blueGrey[700],
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // UPDATED: Dynamic menu access logic
  List<String> _getMenuItemsForRole(String role, String organization) {
    // Define menu items for JV Almacis (service provider)
    final Map<String, List<String>> jvAlmacisMenus = {
      'Admin': [
        'Facilities',
        'Locations',
        'Building Information',
        'Schedule Maintenance',
        'Preventive Maintenance',
        'Reports',
        'Price Lists',
        'Work on Request',
        'Work Orders',
        'Equipment Supplied',
        'Inventory and Parts',
        'Vendors',
        'KPIs',
        'Billing',
        'Report',
        'Settings'
      ],
      'Technician': [
        'Facilities',
        'Locations',
        'Building Information',
        'Preventive Maintenance',
        'Schedule Maintenance',
        'Reports',
        'Price Lists',
        'Work on Request',
        'Work Orders',
        'Equipment Supplied',
        'Inventory and Parts',
        'Billing',
        'Report',
        'Settings'
      ],
    };

    // Define menu items for all other organizations (client organizations)
    final Map<String, List<String>> clientOrganizationMenus = {
      'Admin': [
        'Facilities',
        'Locations',
        'Building Information',
        'Schedule Maintenance',
        'Preventive Maintenance',
        'Reports',
        'Work on Request',
        'Work Orders',
        'Billing',
        'Report',
        'Settings'
      ],
      'Technician': [
        'Facilities',
        'Locations',
        'Building Information',
        'Preventive Maintenance',
        'Schedule Maintenance',
        'Reports',
        'Work on Request',
        'Work Orders',
        'Billing',
        'Report',
        'Settings'
      ],
    };

    // User role always gets the same basic access regardless of organization
    final List<String> userMenus = ['Facilities', 'Settings'];

    // Return appropriate menu items based on role and organization
    if (role == 'User' || organization == '-') {
      return userMenus;
    } else if (organization == 'JV Almacis') {
      return jvAlmacisMenus[role] ?? userMenus;
    } else {
      // All other organizations get the client organization menus
      return clientOrganizationMenus[role] ?? userMenus;
    }
  }

  List<Widget> _buildMenuItems() {
    final role = _currentRole;
    final org = _organization;

    final menuStructure = [
      {'title': 'Facilities', 'icon': Icons.business, 'isSubItem': false},
      {'title': 'Locations', 'icon': Icons.location_on, 'isSubItem': false},
      {'title': 'Building Information', 'icon': Icons.info, 'isSubItem': false, 'isParent': true},
      {'title': 'Schedule Maintenance', 'icon': Icons.event, 'isSubItem': false},
      {'title': 'Preventive Maintenance', 'icon': Icons.build_circle, 'isSubItem': false},
      {'title': 'Reports', 'icon': Icons.bar_chart, 'isSubItem': false},
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

    final buildingInfoSubItems = [
      {'title': 'Building Survey', 'icon': Icons.account_balance},
      {'title': 'Documentations', 'icon': Icons.description},
      {'title': 'Drawings', 'icon': Icons.brush},
    ];

    // Use the new dynamic method to get allowed items
    final allowedItems = _getMenuItemsForRole(role, org);
    final List<Widget> menuWidgets = [];

    _logger.i('Building menu for role: $role, org: $org, allowed items: $allowedItems');

    for (var menuItem in menuStructure) {
      final itemTitle = menuItem['title'] as String;
      if (!allowedItems.contains(itemTitle)) {
        continue;
      }
      final icon = menuItem['icon'] as IconData;
      final isSubItem = menuItem['isSubItem'] as bool;
      final isParent = menuItem['isParent'] as bool? ?? false;

      if (isParent && itemTitle == 'Building Information') {
        menuWidgets.add(
          ListTile(
            leading: Icon(icon, color: Colors.blueGrey),
            title: Text(itemTitle, style: GoogleFonts.poppins()),
            trailing: Icon(
              _isBuildingInfoExpanded ? Icons.expand_less : Icons.expand_more,
              color: Colors.blueGrey,
            ),
            onTap: () {
              setState(() {
                _isBuildingInfoExpanded = !_isBuildingInfoExpanded;
              });
              _logger.i('Building Information menu ${_isBuildingInfoExpanded ? 'expanded' : 'collapsed'}');
            },
          ),
        );

        if (_isBuildingInfoExpanded) {
          for (var subItem in buildingInfoSubItems) {
            final subTitle = subItem['title'] as String;
            final subIcon = subItem['icon'] as IconData;
            
            menuWidgets.add(
              ListTile(
                contentPadding: const EdgeInsets.only(left: 32.0, right: 16.0),
                leading: Icon(subIcon, color: Colors.blueGrey[600], size: 20),
                title: Text(
                  subTitle, 
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.blueGrey[700],
                  ),
                ),
                onTap: () {
                  _logger.i('Sub-menu item clicked: $subTitle, expansion state preserved');
                  _handleSubMenuNavigation(subTitle);
                },
              ),
            );
          }
        }
      } else if (!isParent) {
        if (!['Building Survey', 'Documentations', 'Drawings'].contains(itemTitle)) {
          menuWidgets.add(
            ListTile(
              contentPadding:
                  isSubItem ? const EdgeInsets.only(left: 32.0, right: 16.0) : null,
              leading: Icon(icon, color: Colors.blueGrey),
              title: Text(itemTitle, style: GoogleFonts.poppins()),
              onTap: () => _handleMenuNavigation(itemTitle),
            ),
          );
        }
      }
    }

    return menuWidgets;
  }

  void _handleSubMenuNavigation(String title) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;
    
    if (isMobile) {
      Navigator.pop(context);
      _logger.i('Closed drawer for sub-menu navigation to $title, expansion state preserved');
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
      _logger.w('Sub-menu navigation blocked: No facility selected for $title, facilityId: ${widget.facilityId}');
      return;
    }

    final screenMap = {
      'Building Survey': () => BuildingSurveyScreen(
          facilityId: widget.facilityId, selectedSubSection: ''),
      'Documentations': () =>
          DocumentationsScreen(facilityId: widget.facilityId),
      'Drawings': () => DrawingsScreen(facilityId: widget.facilityId),
    };

    final screenBuilder = screenMap[title];
    if (screenBuilder != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => screenBuilder()),
      );
      _logger.i('Navigated to sub-menu $title screen, facilityId: ${widget.facilityId}');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$title feature not found', style: GoogleFonts.poppins()),
        ),
      );
      _logger.w('Sub-menu navigation failed: $title feature not found');
    }
  }

  void _handleMenuNavigation(String title) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;
    if (isMobile) {
      Navigator.pop(context);
      _logger.i('Closed drawer for navigation to $title');
    }

    if (title == 'Facilities') {
      widget.onFacilityReset?.call();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) =>
              const DashboardScreen(facilityId: '', role: 'User'),
        ),
        (route) => false,
      );
      _logger.i(
          'Navigated to DashboardScreen for facility selection, facilityId: ""');
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
      _logger.w('Navigation blocked: No facility selected for $title, facilityId: ${widget.facilityId}');
      return;
    }

    final screenMap = {
      'Locations': () => LocationsScreen(facilityId: widget.facilityId),
      'Schedule Maintenance': () =>
          ScheduleMaintenanceScreen(facilityId: widget.facilityId),
      'Preventive Maintenance': () =>
          PreventiveMaintenanceScreen(facilityId: widget.facilityId),
      'Reports': () => ReportsScreen(facilityId: widget.facilityId),
      'Work on Request': () => RequestScreen(facilityId: widget.facilityId),
      'Work Orders': () => WorkOrderScreen(facilityId: widget.facilityId),
      'Price Lists': () => PriceListScreen(facilityId: widget.facilityId),
      'Billing': () =>
          BillingScreen(facilityId: widget.facilityId, userRole: _currentRole),
      'Equipment Supplied': () =>
          EquipmentSuppliedScreen(facilityId: widget.facilityId),
      'Inventory and Parts': () =>
          InventoryScreen(facilityId: widget.facilityId),
      'Vendors': () => VendorScreen(facilityId: widget.facilityId),
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
      _logger.i('Navigated to $title screen, facilityId: ${widget.facilityId}');
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