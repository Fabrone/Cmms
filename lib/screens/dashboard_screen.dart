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
  String? _currentRole;
  bool _isDeveloper = false;
  String? _selectedFacilityId;
  String? _organization;
  bool _isFacilitySelectionActive = true;

  @override
  void initState() {
    super.initState();
    _currentRole = widget.role == 'Unknown' ? 'User' : widget.role;
    _selectedFacilityId = null;
    _isFacilitySelectionActive = true;
    _initializeRoleListeners();
  }

  Future<void> _initializeRoleListeners() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _redirectToLogin('No user logged in');
      return;
    }

    logger.i('Initializing role for UID: ${user.uid}');

    try {
      // Check collections in order of priority
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

      if (mounted) {
        setState(() {
          _isDeveloper = developerDoc.exists;
          
          // Check admin first - highest priority
          if (adminDoc.exists) {
            _currentRole = 'Admin';
            _organization = adminDoc.data()?['organization'] ?? '-';
            logger.i('User is an Admin with organization: $_organization');
          } 
          // Then check developer
          else if (developerDoc.exists) {
            _currentRole = 'Technician'; // Developers are treated as Technicians
            _organization = 'JV Almacis'; // Developers are under JV Almacis
            logger.i('User is a Developer treated as Technician for JV Almacis');
          } 
          // Then check technician
          else if (technicianDoc.exists) {
            _currentRole = 'Technician';
            _organization = technicianDoc.data()?['organization'] ?? '-';
            logger.i('User is a Technician with organization: $_organization');
          } 
          // Finally check user collection for technician role
          else if (userDoc.exists && userDoc.data()?['role'] == 'Technician') {
            _currentRole = 'Technician';
            // Check if they have a technician document for organization
            _organization = technicianDoc.exists && technicianDoc.data()?['organization'] != null
                ? technicianDoc.data()!['organization']
                : '-';
            logger.i('User has Technician role in Users collection with organization: $_organization');
          } 
          // Default to User
          else {
            _currentRole = 'User';
            _organization = '-';
            logger.i('User has default User role');
          }
          
          logger.i(
            'Initial role set: $_currentRole, Organization: $_organization, IsDeveloper: $_isDeveloper, TechnicianDoc: ${technicianDoc.exists}, UserRole: ${userDoc.exists ? (userDoc.data()?['role'] ?? 'N/A') : 'N/A'}',
          );
        });
      }

      _listenToRoleChanges(user.uid);
    } catch (e) {
      logger.e('Error initializing role: $e');
      if (mounted) {
        setState(() {
          _currentRole = 'User';
          _organization = '-';
        });
      }
    }
  }

  void _listenToRoleChanges(String uid) {
    const roleCollections = ['Admins', 'Developers', 'Technicians'];

    for (String collection in roleCollections) {
      FirebaseFirestore.instance
          .collection(collection)
          .doc(uid)
          .snapshots()
          .listen((snapshot) async {
        if (mounted) {
          // Get fresh technician data for organization info
          final technicianDoc = await FirebaseFirestore.instance
              .collection('Technicians')
              .doc(uid)
              .get();
          
          setState(() {
            if (snapshot.exists) {
              if (collection == 'Admins') {
                _currentRole = 'Admin';
                _organization = snapshot.data()?['organization'] ?? '-';
                logger.i('Role updated to Admin with organization: $_organization');
              } else if (collection == 'Developers') {
                _isDeveloper = true;
                _currentRole = 'Technician'; // Developers are treated as Technicians
                _organization = 'JV Almacis'; // Developers are under JV Almacis
                logger.i('Role updated to Developer (treated as Technician) for JV Almacis');
              } else if (collection == 'Technicians') {
                // Only update to Technician if not already an Admin
                if (_currentRole != 'Admin') {
                  _currentRole = 'Technician';
                  _organization = snapshot.data()?['organization'] ?? '-';
                  logger.i('Role updated to Technician with organization: $_organization');
                }
              }
            } else {
              if (collection == 'Developers') {
                _isDeveloper = false;
                // If no longer a developer, check if still a technician or admin
                if (_currentRole != 'Admin' && technicianDoc.exists) {
                  _currentRole = 'Technician';
                  _organization = technicianDoc.data()?['organization'] ?? '-';
                  logger.i('No longer a Developer, but still a Technician with organization: $_organization');
                } else if (_currentRole != 'Admin') {
                  // Check Users collection for technician role
                  FirebaseFirestore.instance.collection('Users').doc(uid).get().then((userDoc) {
                    if (mounted && userDoc.exists && userDoc.data()?['role'] == 'Technician') {
                      setState(() {
                        _currentRole = 'Technician';
                        _organization = technicianDoc.exists && technicianDoc.data()?['organization'] != null
                            ? technicianDoc.data()!['organization']
                            : '-';
                        logger.i('Role updated to Technician from Users collection with organization: $_organization');
                      });
                    } else if (mounted && _currentRole != 'Admin') {
                      setState(() {
                        _currentRole = 'User';
                        _organization = '-';
                        logger.i('Role updated to default User');
                      });
                    }
                  });
                }
              } else if (collection == 'Admins' && _currentRole == 'Admin') {
                // If admin document was deleted, check other roles
                _checkRolePriority(uid);
                logger.i('Admin document removed, checking other roles');
              } else if (collection == 'Technicians' && _currentRole == 'Technician' && !_isDeveloper) {
                // If technician document was deleted and not a developer, check user role
                FirebaseFirestore.instance.collection('Users').doc(uid).get().then((userDoc) {
                  if (mounted && userDoc.exists && userDoc.data()?['role'] == 'Technician') {
                    setState(() {
                      _currentRole = 'Technician';
                      _organization = '-';
                      logger.i('Technician document removed but still has Technician role in Users');
                    });
                  } else if (mounted) {
                    setState(() {
                      _currentRole = 'User';
                      _organization = '-';
                      logger.i('Technician document removed, role updated to User');
                    });
                  }
                });
              }
            }
            logger.i('Snapshot update for $collection, Role: $_currentRole, Organization: $_organization, IsDeveloper: $_isDeveloper');
          });
        }
      }, onError: (e) {
        logger.e('Error listening to $collection role: $e');
      });
    }

    FirebaseFirestore.instance.collection('Users').doc(uid).snapshots().listen((snapshot) async {
      if (mounted && snapshot.exists) {
        final role = snapshot.data()?['role'] ?? '-';
        if (role == 'Technician' && _currentRole != 'Admin' && !_isDeveloper) {
          final techDoc = await FirebaseFirestore.instance.collection('Technicians').doc(uid).get();
          setState(() {
            _currentRole = 'Technician';
            _organization = techDoc.exists && techDoc.data()?['organization'] != null
                ? techDoc.data()!['organization']
                : '-';
          });
          logger.i('Users collection updated role to Technician, Organization: $_organization');
        }
      }
    }, onError: (e) {
      logger.e('Error listening to Users role: $e');
    });

    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null && mounted) {
        _redirectToLogin('User logged out');
      }
    });
  }

  Future<void> _checkRolePriority(String uid) async {
    if (!mounted) return;
    
    try {
      final developerDoc = await FirebaseFirestore.instance
          .collection('Developers')
          .doc(uid)
          .get();
      
      final technicianDoc = await FirebaseFirestore.instance
          .collection('Technicians')
          .doc(uid)
          .get();
      
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(uid)
          .get();
      
      if (mounted) {
        setState(() {
          if (developerDoc.exists) {
            _isDeveloper = true;
            _currentRole = 'Technician';
            _organization = 'JV Almacis';
          } else if (technicianDoc.exists) {
            _currentRole = 'Technician';
            _organization = technicianDoc.data()?['organization'] ?? '-';
          } else if (userDoc.exists && userDoc.data()?['role'] == 'Technician') {
            _currentRole = 'Technician';
            _organization = '-';
          } else {
            _currentRole = 'User';
            _organization = '-';
          }
        });
      }
    } catch (e) {
      logger.e('Error checking role priority: $e');
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
        'Facilities', 'Locations', 'Schedule Maintenance', 'Preventive Maintenance',
        'Reports', 'Price Lists', 'Work on Request', 'Work Orders', 'Equipment Supplied',
        'Inventory and Parts', 'Billing', 'Settings'
      ],
    },
  };

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTabletOrWeb = screenWidth > 600;
    final displayRole = _currentRole ?? 'User';
    final isFacilitySelected = _selectedFacilityId != null && _selectedFacilityId!.isNotEmpty;

    return PopScope(
      canPop: !isFacilitySelected,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isFacilitySelected) {
          _resetFacilitySelection();
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
              // Only show menu button on mobile when facility is selected
              leading: !isTabletOrWeb && isFacilitySelected
                  ? Builder(
                      builder: (context) => IconButton(
                        icon: const Icon(Icons.menu, color: Colors.white, size: 40),
                        onPressed: () {
                          Scaffold.of(context).openDrawer();
                        },
                        tooltip: 'Open Menu',
                      ),
                    )
                  : null,
              title: Text(
                isFacilitySelected 
                    ? '$displayRole Dashboard${_organization != '-' ? ' ($_organization)' : ''}'
                    : 'Select Facility',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
              backgroundColor: Colors.blueGrey,
              actions: [
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
    final role = _currentRole ?? 'User';
    final org = _organization ?? '-';
    
    // Get menu items based on role and organization
    final allowedItems = _roleMenuAccess[role]?[org] ?? _roleMenuAccess['User']!['-']!;
    
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
            onTap: _resetFacilitySelection,
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

    final role = _currentRole ?? 'User';
    if (role == 'User') {
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
          'Facilities': () => FacilityScreen(
            selectedFacilityId: _selectedFacilityId,
            onFacilitySelected: _onFacilitySelected,
            isSelectionActive: true,
          ),
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
          'Billing': () => BillingScreen(facilityId: _selectedFacilityId!, userRole: _currentRole ?? 'User'),
        };

        final screenBuilder = screenMap[title];
        if (screenBuilder != null) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => screenBuilder()),
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