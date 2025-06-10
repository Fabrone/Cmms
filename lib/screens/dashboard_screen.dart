import 'package:cmms/developer/developer_screen.dart';
import 'package:cmms/display%20screens/billing_screen.dart';
import 'package:cmms/display%20screens/building_survey_screen.dart';
import 'package:cmms/display%20screens/documentations_screen.dart';
import 'package:cmms/display%20screens/drawings_screen.dart';
import 'package:cmms/display%20screens/equipment_supplied_screen.dart';
import 'package:cmms/display%20screens/facility_screen.dart';
import 'package:cmms/display%20screens/inventory_screen.dart';
import 'package:cmms/display%20screens/kpi_screen.dart';
import 'package:cmms/display%20screens/locations_screen.dart';
import 'package:cmms/display%20screens/price_list_screen.dart';
import 'package:cmms/display%20screens/report_screen.dart';
import 'package:cmms/display%20screens/reports_screen.dart';
import 'package:cmms/display%20screens/request_screen.dart';
import 'package:cmms/display%20screens/role_assignment_screen.dart';
import 'package:cmms/display%20screens/schedule_maintenance_screen.dart';
import 'package:cmms/display%20screens/vendor_screen.dart';
import 'package:cmms/display%20screens/work_order_screen.dart';
import 'package:cmms/screens/user_screen.dart';
import 'package:cmms/screens/settings_screen.dart';
import 'package:cmms/technician/preventive_maintenance_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/authentication/login_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Add this import at the top of the file
import 'dart:async';

class DashboardScreen extends StatefulWidget {
  final String facilityId;
  final String role;

  const DashboardScreen({super.key, required this.facilityId, required this.role});

  @override
  DashboardScreenState createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  final logger = Logger(printer: PrettyPrinter());
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _currentRole = 'User';
  bool _isDeveloper = false;
  String? _selectedFacilityId;
  String _organization = '-';
  bool _isFacilitySelectionActive = true;
  
  // Stream subscriptions for role listeners
  List<StreamSubscription<DocumentSnapshot>> _roleSubscriptions = [];
  
  @override
  void initState() {
    super.initState();
    _currentRole = widget.role == 'Unknown' ? 'User' : widget.role;
    
    // Only set facility selection active if no facility ID is provided
    _selectedFacilityId = widget.facilityId.isNotEmpty ? widget.facilityId : null;
    _isFacilitySelectionActive = widget.facilityId.isEmpty;
    
    // Initialize role checking
    _checkUserRole();
  }
  
  @override
  void dispose() {
    // Cancel all stream subscriptions
    for (var subscription in _roleSubscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  // Comprehensive role checking system
  Future<void> _checkUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _redirectToLogin('No user logged in');
      return;
    }

    logger.i('Checking roles for user: ${user.uid}');
    
    // Cancel any existing subscriptions
    for (var subscription in _roleSubscriptions) {
      subscription.cancel();
    }
    _roleSubscriptions = [];
    
    // Set up real-time listeners for all role collections
    _setupRoleListener('Admins', user.uid);
    _setupRoleListener('Developers', user.uid);
    _setupRoleListener('Technicians', user.uid);
    _setupRoleListener('Users', user.uid);
    
    // Initial role check
    await _updateUserRole(user.uid);
  }
  
  // Set up a real-time listener for a specific role collection
  void _setupRoleListener(String collection, String uid) {
    final stream = FirebaseFirestore.instance
        .collection(collection)
        .doc(uid)
        .snapshots();
    
    final subscription = stream.listen(
      (snapshot) {
        logger.i('Role update detected in $collection for $uid');
        _updateUserRole(uid);
      },
      onError: (error) {
        logger.e('Error in $collection listener: $error');
      }
    );
    
    _roleSubscriptions.add(subscription);
  }

  // Comprehensive role update logic
  Future<void> _updateUserRole(String uid) async {
    try {
      logger.i('Updating user role for $uid');
      
      // Get all role documents
      final adminDoc = await FirebaseFirestore.instance.collection('Admins').doc(uid).get();
      final developerDoc = await FirebaseFirestore.instance.collection('Developers').doc(uid).get();
      final technicianDoc = await FirebaseFirestore.instance.collection('Technicians').doc(uid).get();
      final userDoc = await FirebaseFirestore.instance.collection('Users').doc(uid).get();
      
      // Determine role based on priority
      String newRole = 'User';
      String newOrg = '-';
      bool isDev = false;
      
      // Log document existence for debugging
      logger.i('Role documents: Admin=${adminDoc.exists}, Developer=${developerDoc.exists}, Technician=${technicianDoc.exists}, User=${userDoc.exists}');
      
      if (adminDoc.exists) {
        // Admin has highest priority
        newRole = 'Admin';
        final adminData = adminDoc.data();
        newOrg = adminData?['organization'] ?? '-';
        logger.i('User is an Admin for organization: $newOrg');
      } 
      else if (developerDoc.exists) {
        // Developer is treated as Technician for JV Almacis
        newRole = 'Technician';
        newOrg = 'JV Almacis';
        isDev = true;
        logger.i('User is a Developer (treated as Technician) for JV Almacis');
      }
      else if (technicianDoc.exists) {
        // Regular Technician
        newRole = 'Technician';
        final techData = technicianDoc.data();
        newOrg = techData?['organization'] ?? '-';
        logger.i('User is a Technician for organization: $newOrg');
      }
      else if (userDoc.exists) {
        // Check if user has Technician role in Users collection
        final userData = userDoc.data();
        if (userData != null && userData['role'] == 'Technician') {
          newRole = 'Technician';
          newOrg = '-';
          logger.i('User has Technician role in Users collection');
        } else {
          newRole = 'User';
          newOrg = '-';
          logger.i('User has regular User role');
        }
      }
      
      // Update state if mounted and role has changed
      if (mounted) {
        setState(() {
          _currentRole = newRole;
          _organization = newOrg;
          _isDeveloper = isDev;
        });
        
        logger.i('Role updated: $_currentRole, Organization: $_organization, IsDeveloper: $_isDeveloper');
        
        // Show notification of role change
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              'Your role is now: $_currentRole${_organization != '-' ? ' ($_organization)' : ''}',
              style: GoogleFonts.poppins(),
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.blueGrey[700],
          ),
        );
      }
    } catch (e) {
      logger.e('Error updating user role: $e');
      if (mounted) {
        setState(() {
          _currentRole = 'User';
          _organization = '-';
          _isDeveloper = false;
        });
      }
    }
  }

  Future<void> _redirectToLogin(String message) async {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(message, style: GoogleFonts.poppins())),
      );
    }
  }

  void _onFacilitySelected(String facilityId) {
    setState(() {
      _selectedFacilityId = facilityId;
      _isFacilitySelectionActive = false;
    });
    logger.i('Selected facility: $facilityId');
    
    // Open the drawer automatically after facility selection on mobile
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;
    
    if (isMobile) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _scaffoldKey.currentState != null && !_scaffoldKey.currentState!.isDrawerOpen) {
          _scaffoldKey.currentState!.openDrawer();
          logger.i('Automatically opened drawer after facility selection');
        }
      });
    }
  }

  void _resetFacilitySelection() {
    setState(() {
      _selectedFacilityId = null;
      _isFacilitySelectionActive = true;
    });
    logger.i('Reset facility selection');
  }

  void _refreshFacilitiesView() {
    setState(() {
      _selectedFacilityId = null;
      _isFacilitySelectionActive = true;
    });
    
    // Show feedback that facilities are being refreshed
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          'Facilities refreshed',
          style: GoogleFonts.poppins(),
        ),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.blueGrey[600],
      ),
    );
    
    logger.i('Facilities view refreshed - showing facility selection interface');
  }

  // Handle back button press with proper navigation logic
  void _handleBackNavigation() {
    // Check if there's a previous screen in the navigation stack
    if (Navigator.canPop(context)) {
      // There's a previous screen, navigate back to it
      Navigator.pop(context);
      logger.i('Navigated back to previous screen');
    } else {
      // No previous screen - this means dashboard was launched directly
      // Show a message instead of forcing logout
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            'You are at the main dashboard. Use the menu to navigate or logout from Settings.',
            style: GoogleFonts.poppins(),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      logger.i('No previous screen to navigate back to');
    }
  }

  // Define menu structure with main items and sub-items
  final List<Map<String, dynamic>> _menuStructure = [
    {
      'title': 'Facilities',
      'icon': Icons.business,
      'isSubItem': false,
    },
    {
      'title': 'Locations',
      'icon': Icons.location_on,
      'isSubItem': false,
    },
    {
      'title': 'Building Survey',
      'icon': Icons.account_balance,
      'isSubItem': false,
    },
    {
      'title': 'Drawings',
      'icon': Icons.brush,
      'isSubItem': true, // Sub-item of Building Survey
    },
    {
      'title': 'Documentations',
      'icon': Icons.description,
      'isSubItem': true, // Sub-item of Building Survey
    },
    {
      'title': 'Schedule Maintenance',
      'icon': Icons.event,
      'isSubItem': false,
    },
    {
      'title': 'Preventive Maintenance',
      'icon': Icons.build_circle,
      'isSubItem': true, // Sub-item of Schedule Maintenance
    },
    {
      'title': 'Reports',
      'icon': Icons.bar_chart,
      'isSubItem': true, // Sub-item of Schedule Maintenance
    },
    {
      'title': 'Work on Request',
      'icon': Icons.request_page,
      'isSubItem': false,
    },
    {
      'title': 'Work Orders',
      'icon': Icons.work,
      'isSubItem': false,
    },
    {
      'title': 'Price Lists',
      'icon': Icons.attach_money,
      'isSubItem': false,
    },
    {
      'title': 'Billing',
      'icon': Icons.receipt_long,
      'isSubItem': false,
    },
    {
      'title': 'Equipment Supplied',
      'icon': Icons.construction,
      'isSubItem': false,
    },
    {
      'title': 'Inventory and Parts',
      'icon': Icons.inventory,
      'isSubItem': false,
    },
    {
      'title': 'Vendors',
      'icon': Icons.store,
      'isSubItem': false,
    },
    {
      'title': 'KPIs',
      'icon': Icons.trending_up,
      'isSubItem': false,
    },
    {
      'title': 'Report',
      'icon': Icons.bar_chart,
      'isSubItem': false,
    },
    {
      'title': 'Settings',
      'icon': Icons.settings,
      'isSubItem': false,
    },
  ];

  // Role-specific menu items
  final Map<String, Map<String, List<String>>> _roleMenuAccess = {
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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTabletOrWeb = screenWidth > 600;
    final displayRole = _currentRole;
    final isFacilitySelected = _selectedFacilityId != null && _selectedFacilityId!.isNotEmpty;

    return PopScope(
      canPop: false, // Prevent accidental logout on web
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (isFacilitySelected) {
            // Reset facility selection instead of popping
            _resetFacilitySelection();
          } else {
            // Show confirmation dialog before logout
            _showLogoutConfirmation();
          }
        }
      },
      child: ScaffoldMessenger(
        key: _messengerKey,
        child: Scaffold(
          key: _scaffoldKey,
          extendBodyBehindAppBar: false,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(80.0),
            child: AppBar(
              // Show back button when in facility selection mode, menu button when facility is selected
              leading: _selectedFacilityId == null
                  ? IconButton(
                      icon: const Icon(
                        Icons.arrow_back, 
                        color: Colors.white, 
                        size: 28,
                      ),
                      onPressed: _handleBackNavigation,
                      tooltip: 'Back',
                    )
                  : (!isTabletOrWeb && isFacilitySelected
                      ? Builder(
                          builder: (context) => IconButton(
                            icon: const Icon(Icons.menu, color: Colors.white, size: 40),
                            onPressed: () {
                              Scaffold.of(context).openDrawer();
                            },
                            tooltip: 'Open Menu',
                          ),
                        )
                      : null),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _currentRole == 'Admin' 
                            ? Icons.admin_panel_settings
                            : _currentRole == 'Technician'
                                ? Icons.engineering
                                : Icons.person,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isFacilitySelected 
                            ? '$displayRole Dashboard'
                            : 'Select Facility',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 24,
                        ),
                      ),
                    ],
                  ),
                  if (isFacilitySelected && _organization != '-')
                    Text(
                      _organization,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.normal,
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
              backgroundColor: Colors.blueGrey,
              actions: [
                // Admin-specific actions
                if (_currentRole == 'Admin' && isFacilitySelected)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: IconButton(
                      icon: const Icon(Icons.person_add, color: Colors.white, size: 40),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const RoleAssignmentScreen()),
                        );
                      },
                      tooltip: 'Assign Technician Role',
                    ),
                  ),
              ],
              elevation: 0,
            ),
          ),
          // Only show drawer on mobile when facility is selected
          drawer: !isTabletOrWeb && isFacilitySelected ? _buildDrawer() : null,
          body: Row(
            children: [
              // Show sidebar on tablet/web when facility is selected
              if (isTabletOrWeb && isFacilitySelected) _buildSidebar(),
              Expanded(
                child: _selectedFacilityId == null
                    ? FacilityScreen(
                        selectedFacilityId: _selectedFacilityId,
                        onFacilitySelected: _onFacilitySelected,
                        isSelectionActive: _isFacilitySelectionActive,
                      )
                    : _buildMainContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutConfirmation() {
    const bool isWebPlatform = kIsWeb;
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Confirm Logout', style: GoogleFonts.poppins()),
          content: Text(
            isWebPlatform 
                ? 'Are you sure you want to logout? This will end your web session.'
                : 'Are you sure you want to logout?', 
            style: GoogleFonts.poppins()
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            TextButton(
              onPressed: () {
                // Close the dialog first
                Navigator.of(dialogContext).pop();
                
                // Create a separate method for logout to avoid async gap
                _performLogout();
              },
              child: Text('Logout', style: GoogleFonts.poppins(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  // New method to handle the async logout operation
  Future<void> _performLogout() async {
    // Web platforms might need special handling for Firebase Auth
    if (kIsWeb) {
      logger.i('Performing web-specific logout');
      // For web, we might need to clear any web-specific storage or state
    }
    
    await FirebaseAuth.instance.signOut();
    
    // Check if the widget is still mounted before using context
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  Widget _buildMainContent() {
    if (_selectedFacilityId == null) {
      return FacilityScreen(
        selectedFacilityId: _selectedFacilityId,
        onFacilitySelected: _onFacilitySelected,
        isSelectionActive: _isFacilitySelectionActive,
      );
    }
    
    // Show facility screen content when facility is selected
    return FacilityScreen(
      selectedFacilityId: _selectedFacilityId,
      onFacilitySelected: _onFacilitySelected,
      isSelectionActive: _isFacilitySelectionActive,
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

  List<Widget> _buildMenuItems() {
    final role = _currentRole;
    final org = _organization;
    
    // Get menu items based on role and organization
    List<String> allowedItems = [];
    
    // First check if this specific role+org combination exists
    if (_roleMenuAccess.containsKey(role) && _roleMenuAccess[role]!.containsKey(org)) {
      allowedItems = _roleMenuAccess[role]![org]!;
    } 
    // If not found, try with default org '-'
    else if (_roleMenuAccess.containsKey(role) && _roleMenuAccess[role]!.containsKey('-')) {
      allowedItems = _roleMenuAccess[role]!['-']!;
    }
    // Fallback to User role with default org
    else {
      allowedItems = _roleMenuAccess['User']!['-']!;
    }
    
    logger.i('Building menu items for role: $role, organization: $org, allowed items: ${allowedItems.length}');

    final List<Widget> menuWidgets = [];
    
    for (var menuItem in _menuStructure) {
      final title = menuItem['title'] as String;
      
      // Skip items not allowed for this role/organization
      if (!allowedItems.contains(title)) {
        continue;
      }
      
      final icon = menuItem['icon'] as IconData;
      final isSubItem = menuItem['isSubItem'] as bool;
      
      // Special handling for "Facilities" item
      if (title == 'Facilities' && _selectedFacilityId != null) {
        menuWidgets.add(
          ListTile(
            leading: Icon(icon, color: Colors.blueGrey),
            title: Text(title, style: GoogleFonts.poppins()),
            onTap: _refreshFacilitiesView,
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
          title: Text(title, style: GoogleFonts.poppins()),
          onTap: () => _handleMenuItemTap(title),
        ),
      );
    }
    
    return menuWidgets;
  }

  Widget _buildAppIcon() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: GestureDetector(
        onTap: _isDeveloper
            ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const DeveloperScreen()),
                );
              }
            : null,
        child: Image.asset(
          'assets/icons/icon.png',
          width: 60,
          height: 60,
        ),
      ),
    );
  }

  void _handleMenuItemTap(String title) {
    if (!mounted) return;

    // Ensure we have a selected facility
    if (_selectedFacilityId == null || _selectedFacilityId!.isEmpty) {
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            'Please select a facility first. If no facilities are available, add a new one.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
      return;
    }

    // Special handling for Settings - always accessible
    if (title != 'Settings' && title != 'Facilities' && _currentRole == 'User') {
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text("Wait for Admin's role assignment to utilize the features", style: GoogleFonts.poppins()),
        ),
      );
      return;
    }

    try {
      if (mounted) {
        // Close drawer if open on mobile
        final screenWidth = MediaQuery.of(context).size.width;
        final isMobile = screenWidth <= 600;
        if (isMobile && Navigator.canPop(context)) {
          Navigator.pop(context);
        }

        final screenMap = {
          'Facilities': () {
            // Refresh/reopen dashboard with facilities list
            _refreshFacilitiesView();
            return null; // Return null to indicate no navigation needed
          },
          'Locations': () => LocationsScreen(facilityId: _selectedFacilityId!),
          'Building Survey': () => BuildingSurveyScreen(facilityId: _selectedFacilityId!, selectedSubSection: ''),
          'Documentations': () => DocumentationsScreen(facilityId: _selectedFacilityId!),
          'Drawings': () => DrawingsScreen(facilityId: _selectedFacilityId!),
          'Schedule Maintenance': () => ScheduleMaintenanceScreen(facilityId: _selectedFacilityId!),
          'Scheduled Maintenance': () => ScheduleMaintenanceScreen(facilityId: _selectedFacilityId!),
          'Preventive Maintenance': () => PreventiveMaintenanceScreen(facilityId: _selectedFacilityId!),
          'Reports': () => ReportsScreen(facilityId: _selectedFacilityId!),
          'Price Lists': () => PriceListScreen(facilityId: _selectedFacilityId!),
          'Work on Request': () => RequestScreen(facilityId: _selectedFacilityId!),
          'Work Orders': () => WorkOrderScreen(facilityId: _selectedFacilityId!),
          'Equipment Supplied': () => EquipmentSuppliedScreen(facilityId: _selectedFacilityId!),
          'Inventory and Parts': () => InventoryScreen(facilityId: _selectedFacilityId!),
          'Vendors': () => VendorScreen(facilityId: _selectedFacilityId!),
          'Users': () => UserScreen(facilityId: _selectedFacilityId!),
          'KPIs': () => KpiScreen(facilityId: _selectedFacilityId!),
          'Report': () => ReportScreen(facilityId: _selectedFacilityId!),
          'Settings': () => SettingsScreen(facilityId: _selectedFacilityId!),
          'Billing': () => BillingScreen(facilityId: _selectedFacilityId!, userRole: _currentRole),
        };

        final screenBuilder = screenMap[title];
        if (screenBuilder != null) {
          final screen = screenBuilder();
          if (screen != null) { // Only navigate if a screen was returned
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => screen),
            ).then((_) {
              logger.i('Successfully navigated to $title with facilityId: $_selectedFacilityId');
            }).catchError((e) {
              logger.e('Error navigating to $title: $e');
              if (mounted && _messengerKey.currentState != null) {
                _messengerKey.currentState!.showSnackBar(
                  SnackBar(
                    content: Text('Error navigating to $title: $e', style: GoogleFonts.poppins()),
                  ),
                );
              }
            });
          }
        } else {
          _messengerKey.currentState?.showSnackBar(
            SnackBar(
              content: Text('$title feature not found', style: GoogleFonts.poppins()),
            ),
          );
        }
      }
    } catch (e) {
      logger.e('Error navigating to $title: $e');
      if (mounted && _messengerKey.currentState != null) {
        _messengerKey.currentState!.showSnackBar(
          SnackBar(
            content: Text('Error navigating to $title: $e', style: GoogleFonts.poppins()),
          ),
        );
      }
    }
  }
}