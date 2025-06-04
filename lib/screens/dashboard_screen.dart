import 'package:cmms/developer/developer_screen.dart';
import 'package:cmms/display%20screens/billing_screen.dart';
import 'package:cmms/display%20screens/building_survey_screen.dart';
import 'package:cmms/display%20screens/documentations_screen.dart';
import 'package:cmms/display%20screens/drawings_screen.dart';
import 'package:cmms/display%20screens/equipment_supplied_screen.dart';
import 'package:cmms/display%20screens/facility_screen.dart';
import 'package:cmms/display%20screens/inventory_screen.dart';
import 'package:cmms/display%20screens/price_list_screen.dart';
import 'package:cmms/display%20screens/reports_screen.dart';
import 'package:cmms/display%20screens/request_screen.dart';
import 'package:cmms/display%20screens/role_assignment_screen.dart';
import 'package:cmms/display%20screens/schedule_maintenance_screen.dart';
import 'package:cmms/display%20screens/work_order_screen.dart';
//import 'package:cmms/screens/equipment_supplied_screen.dart';
//import 'package:cmms/screens/inventory_screen.dart';
import 'package:cmms/screens/kpi_screen.dart';
import 'package:cmms/screens/user_screen.dart';
import 'package:cmms/screens/vendor_screen.dart';
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>(); // Added for drawer control
  String? _currentRole;
  bool _isDeveloper = false;
  String? _selectedFacilityId;
  String? _organization;
  bool _isFacilitySelectionActive = true;

  @override
  void initState() {
    super.initState();
    _currentRole = widget.role == 'Unknown' ? 'User' : widget.role;
    // Always start with no facility selected and facility selection active
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

  // Helper method to check role priority when a role document is removed
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
    
    // Open the drawer automatically after facility selection
    // Use Future.delayed to ensure the state has been updated before opening the drawer
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && _scaffoldKey.currentState != null && !_scaffoldKey.currentState!.isDrawerOpen) {
        _scaffoldKey.currentState!.openDrawer();
        logger.i('Automatically opened drawer after facility selection');
      }
    });
  }

  void _resetFacilitySelection() {
    setState(() {
      _selectedFacilityId = null;
      _isFacilitySelectionActive = true;
    });
    logger.i('Reset facility selection');
  }

  @override
  void dispose() {
    super.dispose();
  }

  // Updated menu items with Settings as the last item
  final Map<String, Map<String, List<Map<String, dynamic>>>> _roleMenuItems = {
    'Admin': {
      'Embassy': [
        {'title': 'Building Survey', 'icon': Icons.account_balance},
        {'title': 'Documentations', 'icon': Icons.description},
        {'title': 'Drawings', 'icon': Icons.brush},
        {'title': 'Schedule Maintenance', 'icon': Icons.event},
        {'title': 'Preventive Maintenance', 'icon': Icons.build_circle},
        {'title': 'Requests', 'icon': Icons.request_page},
        {'title': 'Work Orders', 'icon': Icons.work},
        {'title': 'Billing', 'icon': Icons.receipt_long},
        {'title': 'Settings', 'icon': Icons.settings}, // Settings moved to last
      ],
      'JV Almacis': [
        {'title': 'Building Survey', 'icon': Icons.account_balance},
        {'title': 'Documentations', 'icon': Icons.description},
        {'title': 'Drawings', 'icon': Icons.brush},
        {'title': 'Schedule Maintenance', 'icon': Icons.event},
        {'title': 'Preventive Maintenance', 'icon': Icons.build_circle},
        {'title': 'Reports', 'icon': Icons.bar_chart},
        {'title': 'Price List', 'icon': Icons.attach_money},
        {'title': 'Requests', 'icon': Icons.request_page},
        {'title': 'Work Orders', 'icon': Icons.work},
        {'title': 'Equipment Supplied', 'icon': Icons.construction},
        {'title': 'Inventory and Parts', 'icon': Icons.inventory},
        {'title': 'Vendors', 'icon': Icons.store},
        {'title': 'Users', 'icon': Icons.group},
        {'title': 'KPIs', 'icon': Icons.trending_up},
        {'title': 'Billing', 'icon': Icons.receipt_long},
        {'title': 'Settings', 'icon': Icons.settings}, // Settings moved to last
      ],
    },
    'Technician': {
      'Embassy': [
        {'title': 'Preventive Maintenance', 'icon': Icons.build_circle},
        {'title': 'Schedule Maintenance', 'icon': Icons.event},
        {'title': 'Building Survey', 'icon': Icons.account_balance},
        {'title': 'Documentations', 'icon': Icons.description},
        {'title': 'Drawings', 'icon': Icons.brush},
        {'title': 'Reports', 'icon': Icons.bar_chart},
        {'title': 'Requests', 'icon': Icons.request_page},
        {'title': 'Work Orders', 'icon': Icons.work},
        {'title': 'Billing', 'icon': Icons.receipt_long},
        {'title': 'Settings', 'icon': Icons.settings}, // Settings moved to last
      ],
      'JV Almacis': [
        {'title': 'Preventive Maintenance', 'icon': Icons.build_circle},
        {'title': 'Schedule Maintenance', 'icon': Icons.event},
        {'title': 'Building Survey', 'icon': Icons.account_balance},
        {'title': 'Documentations', 'icon': Icons.description},
        {'title': 'Drawings', 'icon': Icons.brush},
        {'title': 'Reports', 'icon': Icons.bar_chart},
        {'title': 'Price List', 'icon': Icons.attach_money},
        {'title': 'Requests', 'icon': Icons.request_page},
        {'title': 'Work Orders', 'icon': Icons.work},
        {'title': 'Equipment Supplied', 'icon': Icons.construction},
        {'title': 'Inventory and Parts', 'icon': Icons.inventory},
        {'title': 'Billing', 'icon': Icons.receipt_long},
        {'title': 'Settings', 'icon': Icons.settings}, // Settings moved to last
      ],
    },
    'User': {
      '-': [
        {'title': 'Schedule Maintenance', 'icon': Icons.event},
        {'title': 'Preventive Maintenance', 'icon': Icons.build_circle},
        {'title': 'Reports', 'icon': Icons.bar_chart},
        {'title': 'Price List', 'icon': Icons.attach_money},
        {'title': 'Requests', 'icon': Icons.request_page},
        {'title': 'Work Orders', 'icon': Icons.work},
        {'title': 'Equipment Supplied', 'icon': Icons.construction},
        {'title': 'Inventory and Parts', 'icon': Icons.inventory},
        {'title': 'Billing', 'icon': Icons.receipt_long},
        {'title': 'Settings', 'icon': Icons.settings}, // Settings moved to last
      ],
    },
  };

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTabletOrWeb = screenWidth > 600;
    // Show "Technician" in title for both developers and technicians
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
          key: _scaffoldKey, // Added scaffold key for drawer control
          extendBodyBehindAppBar: false,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(80.0),
            child: AppBar(
              // Hide menu button when no facility is selected
              leading: isTabletOrWeb || !isFacilitySelected
                  ? null
                  : Builder(
                      builder: (context) => IconButton(
                        icon: const Icon(Icons.menu, color: Colors.white, size: 40),
                        onPressed: () {
                          Scaffold.of(context).openDrawer();
                        },
                        tooltip: 'Open Menu',
                      ),
                    ),
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
          // Only show drawer when facility is selected
          drawer: isFacilitySelected ? _buildDrawer() : null,
          body: Row(
            children: [
              // Only show sidebar when facility is selected and on tablet/web
              if (isTabletOrWeb && isFacilitySelected) _buildSidebar(),
              Expanded(
                child: FacilityScreen(
                  selectedFacilityId: _selectedFacilityId,
                  onFacilitySelected: _onFacilitySelected,
                  isSelectionActive: _isFacilitySelectionActive,
                ),
              ),
            ],
          ),
        ),
      ),
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
              children: [
                ListTile(
                  leading: const Icon(Icons.add, color: Colors.blueGrey),
                  title: Text('Add New Facility', style: GoogleFonts.poppins()),
                  onTap: _showAddFacilityDialog,
                ),
                ..._buildMenuItems(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddFacilityDialog() async {
    final nameController = TextEditingController();
    final locationController = TextEditingController();
    final addressController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final dialogContext = context;
    final messengerState = _messengerKey.currentState;

    final result = await showDialog<Map<String, String>>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: Text('Add New Facility', style: GoogleFonts.poppins()),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Facility Name',
                  border: const OutlineInputBorder(),
                  labelStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
                validator: (value) => value!.isEmpty ? 'Enter facility name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: locationController,
                decoration: InputDecoration(
                  labelText: 'Location (optional)',
                  border: const OutlineInputBorder(),
                  labelStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: addressController,
                decoration: InputDecoration(
                  labelText: 'Address (optional)',
                  border: const OutlineInputBorder(),
                  labelStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, {
                  'name': nameController.text.trim(),
                  'location': locationController.text.trim(),
                  'address': addressController.text.trim(),
                });
              }
            },
            child: Text('Add', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          messengerState?.showSnackBar(
            SnackBar(content: Text('Please log in to add a facility', style: GoogleFonts.poppins())),
          );
          return;
        }
        final facilityRef = await FirebaseFirestore.instance.collection('Facilities').add({
          'name': result['name'],
          'location': result['location'],
          'address': result['address']!.isNotEmpty ? result['address'] : null,
          'createdBy': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        final newFacilityId = facilityRef.id;
        logger.i('Added new facility: ${result['name']}, ID: $newFacilityId');
        setState(() {
          _selectedFacilityId = newFacilityId;
          _isFacilitySelectionActive = false;
        });
        
        // Automatically open drawer after adding a new facility
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && _scaffoldKey.currentState != null && !_scaffoldKey.currentState!.isDrawerOpen) {
            _scaffoldKey.currentState!.openDrawer();
            logger.i('Automatically opened drawer after adding new facility');
          }
        });
        
        messengerState?.showSnackBar(
          SnackBar(content: Text('Facility added successfully', style: GoogleFonts.poppins())),
        );
      } catch (e) {
        logger.e('Error adding facility: $e');
        messengerState?.showSnackBar(
          SnackBar(content: Text('Error adding facility: $e', style: GoogleFonts.poppins())),
        );
      }
    }
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
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }

        final screenMap = {
          'Building Survey': () => BuildingSurveyScreen(facilityId: _selectedFacilityId!, selectedSubSection: ''),
          'Documentations': () => DocumentationsScreen(facilityId: _selectedFacilityId!),
          'Drawings': () => DrawingsScreen(facilityId: _selectedFacilityId!),
          'Schedule Maintenance': () => ScheduleMaintenanceScreen(facilityId: _selectedFacilityId!),
          'Scheduled Maintenance': () => ScheduleMaintenanceScreen(facilityId: _selectedFacilityId!),
          'Preventive Maintenance': () => PreventiveMaintenanceScreen(facilityId: _selectedFacilityId!),
          'Reports': () => ReportsScreen(facilityId: _selectedFacilityId!),
          'Price List': () => PriceListScreen(facilityId: _selectedFacilityId!),
          'Requests': () => RequestScreen(facilityId: _selectedFacilityId!),
          'Work Orders': () => WorkOrderScreen(facilityId: _selectedFacilityId!),
          'Equipment Supplied': () => EquipmentSuppliedScreen(facilityId: _selectedFacilityId!),
          'Inventory and Parts': () => InventoryScreen(facilityId: _selectedFacilityId!),
          'Vendors': () => VendorScreen(facilityId: _selectedFacilityId!),
          'Users': () => UserScreen(facilityId: _selectedFacilityId!),
          'KPIs': () => KpiScreen(facilityId: _selectedFacilityId!),
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

  List<Widget> _buildMenuItems() {
    final role = _currentRole ?? 'User';
    final org = _organization ?? '-';
    
    // Get menu items based on role and organization
    final menuItems = _roleMenuItems[role]?[org] ?? _roleMenuItems['User']!['-']!;

    logger.i('Building menu items for role: $role, organization: $org, items: ${menuItems.length}');

    return menuItems.map((item) {
      return ListTile(
        leading: Icon(item['icon'], color: Colors.blueGrey),
        title: Text(item['title'], style: GoogleFonts.poppins()),
        onTap: () => _handleMenuItemTap(item['title']),
      );
    }).toList();
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
}
