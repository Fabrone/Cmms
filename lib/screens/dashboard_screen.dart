import 'package:cmms/developer/developer_screen.dart';
import 'package:cmms/display%20screens/facility_screen.dart';
import 'package:cmms/display%20screens/reports_screen.dart';
//import 'package:cmms/display%20screens/preventive_maintenance_screen.dart';
import 'package:cmms/display%20screens/role_assignment_screen.dart';
import 'package:cmms/display%20screens/schedule_maintenance_screen.dart';
import 'package:cmms/screens/building_survey_screen.dart';
import 'package:cmms/screens/documentations_screen.dart';
import 'package:cmms/screens/drawings_screen.dart';
import 'package:cmms/screens/equipment_supplied_screen.dart';
import 'package:cmms/screens/inventory_screen.dart';
import 'package:cmms/screens/kpi_screen.dart';
import 'package:cmms/screens/price_list_screen.dart';
//import 'package:cmms/screens/reports_screen.dart';
import 'package:cmms/screens/request_screen.dart';
import 'package:cmms/screens/user_screen.dart';
import 'package:cmms/screens/vendor_screen.dart';
import 'package:cmms/screens/work_order_screen.dart';
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
  String? _currentRole;
  bool _isDeveloper = false;
  String? _selectedFacilityId;
  String? _organization;
  bool _isFacilitySelectionActive = true;

  @override
  void initState() {
    super.initState();
    _currentRole = widget.role == 'Unknown' ? 'User' : widget.role;
    _selectedFacilityId = widget.facilityId.isNotEmpty ? widget.facilityId : null;
    _isFacilitySelectionActive = _selectedFacilityId == null;
    _initializeRoleListeners();
  }

  Future<void> _initializeRoleListeners() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _redirectToLogin('No user logged in');
      return;
    }

    logger.i('Initializing role for UID: ${user.uid}');

    final developerDoc = await FirebaseFirestore.instance
        .collection('Developers')
        .doc(user.uid)
        .get();
    final adminDoc = await FirebaseFirestore.instance
        .collection('Admins')
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
        if (adminDoc.exists) {
          _currentRole = 'Admin';
          _organization = adminDoc.data()?['organization'] ?? '-';
        } else if (developerDoc.exists) {
          _currentRole = 'Developer';
          _organization = technicianDoc.exists && technicianDoc.data()?['organization'] != null
              ? technicianDoc.data()!['organization']
              : '-';
        } else if (technicianDoc.exists || (userDoc.exists && userDoc.data()?['role'] == 'Technician')) {
          _currentRole = 'Technician';
          _organization = technicianDoc.exists && technicianDoc.data()?['organization'] != null
              ? technicianDoc.data()!['organization']
              : '-';
        } else {
          _currentRole = 'User';
          _organization = '-';
        }
        logger.i(
          'Initial role set: $_currentRole, Organization: $_organization, TechnicianDoc: ${technicianDoc.exists}, UserRole: ${userDoc.exists ? (userDoc.data()?['role'] ?? 'N/A') : 'N/A'}',
        );
      });
    }

    _listenToRoleChanges(user.uid);
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
          setState(() {
            if (snapshot.exists) {
              _currentRole = collection == 'Admins'
                  ? 'Admin'
                  : collection == 'Developers'
                      ? 'Developer'
                      : 'Technician';
              if (collection == 'Developers') {
                _isDeveloper = true;
              }
              if (collection == 'Admins' || collection == 'Technicians') {
                _organization = snapshot.data()?['organization'] ?? '-';
              }
            } else {
              _isDeveloper = collection == 'Developers' ? false : _isDeveloper;
              if (!['Admins', 'Developers', 'Technicians']
                  .any((coll) => coll != collection && _currentRole == (coll == 'Admins' ? 'Admin' : coll.replaceAll('s', '')))) {
                FirebaseFirestore.instance.collection('Users').doc(uid).get().then((userDoc) {
                  if (mounted && userDoc.exists && userDoc.data()?['role'] == 'Technician') {
                    FirebaseFirestore.instance.collection('Technicians').doc(uid).get().then((techDoc) {
                      if (mounted) {
                        setState(() {
                          _currentRole = 'Technician';
                          _organization = techDoc.exists && techDoc.data()?['organization'] != null
                              ? techDoc.data()!['organization']
                              : '-';
                        });
                      }
                    });
                  } else if (mounted) {
                    setState(() {
                      _currentRole = 'User';
                      _organization = '-';
                    });
                  }
                  logger.i('Role after snapshot check: $_currentRole, Organization: $_organization');
                });
              }
            }
            logger.i('Snapshot update for $collection, Role: $_currentRole, Organization: $_organization');
          });
        }
      }, onError: (e) {
        logger.e('Error listening to $collection role: $e');
      });
    }

    FirebaseFirestore.instance.collection('Users').doc(uid).snapshots().listen((snapshot) async {
      if (mounted && snapshot.exists) {
        final role = snapshot.data()?['role'] ?? '-';
        if (role == 'Technician' && _currentRole != 'Admin' && _currentRole != 'Developer') {
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

  Future<void> _handleLogout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error logging out: $e', style: GoogleFonts.poppins())),
        );
      }
      logger.e('Error logging out: $e');
    }
  }

  void _onFacilitySelected(String facilityId) {
    setState(() {
      _selectedFacilityId = facilityId;
      _isFacilitySelectionActive = false;
    });
    logger.i('Selected facility: $facilityId');
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

  final Map<String, Map<String, List<Map<String, dynamic>>>> _roleMenuItems = {
    'Admin': {
      'Embassy': [
        {'title': 'Building Survey', 'icon': Icons.account_balance},
        {'title': 'Schedule Maintenance', 'icon': Icons.event},
        {'title': 'Requests', 'icon': Icons.request_page},
        {'title': 'Work Orders', 'icon': Icons.work},
      ],
      'JV Almacis': [
        {'title': 'Building Survey', 'icon': Icons.account_balance},
        {'title': 'Documentations', 'icon': Icons.description},
        {'title': 'Drawings', 'icon': Icons.brush},
        {'title': 'Scheduled Maintenance', 'icon': Icons.event},
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
      ],
    },
    'Technician': {
      'Embassy': [
        {'title': 'Scheduled Maintenance', 'icon': Icons.event},
        {'title': 'Preventive Maintenance', 'icon': Icons.build_circle},
        {'title': 'Reports', 'icon': Icons.bar_chart},
        {'title': 'Price List', 'icon': Icons.attach_money},
        {'title': 'Requests', 'icon': Icons.request_page},
        {'title': 'Work Orders', 'icon': Icons.work},
      ],
      'JV Almacis': [
        {'title': 'Scheduled Maintenance', 'icon': Icons.event},
        {'title': 'Preventive Maintenance', 'icon': Icons.build_circle},
        {'title': 'Reports', 'icon': Icons.bar_chart},
        {'title': 'Price List', 'icon': Icons.attach_money},
        {'title': 'Requests', 'icon': Icons.request_page},
        {'title': 'Work Orders', 'icon': Icons.work},
        {'title': 'Equipment Supplied', 'icon': Icons.construction},
        {'title': 'Inventory and Parts', 'icon': Icons.inventory},
      ],
    },
    'User': {
      '-': [
        {'title': 'Scheduled Maintenance', 'icon': Icons.event},
        {'title': 'Preventive Maintenance', 'icon': Icons.build_circle},
        {'title': 'Reports', 'icon': Icons.bar_chart},
        {'title': 'Price List', 'icon': Icons.attach_money},
        {'title': 'Requests', 'icon': Icons.request_page},
        {'title': 'Work Orders', 'icon': Icons.work},
        {'title': 'Equipment Supplied', 'icon': Icons.construction},
        {'title': 'Inventory and Parts', 'icon': Icons.inventory},
      ],
    },
  };

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTabletOrWeb = screenWidth > 600;
    final displayRole = _currentRole == 'Developer' ? 'Technician' : _currentRole ?? 'User';
    final isFacilitySelected = _selectedFacilityId != null && _selectedFacilityId!.isNotEmpty;

    return ScaffoldMessenger(
      key: _messengerKey,
      child: PopScope(
        canPop: !isFacilitySelected,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && isFacilitySelected) {
            _resetFacilitySelection();
          }
        },
        child: Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(80.0),
            child: AppBar(
              leading: isTabletOrWeb || !isFacilitySelected
                  ? null
                  : Builder(
                      builder: (context) => IconButton(
                        icon: const Icon(Icons.menu, color: Colors.white, size: 40),
                        onPressed: isFacilitySelected
                            ? () {
                                Scaffold.of(context).openDrawer();
                              }
                            : null,
                        tooltip: isFacilitySelected ? 'Open Menu' : 'Select a facility first',
                      ),
                    ),
              title: Text(
                '$displayRole Dashboard${_organization != '-' ? ' ($_organization)' : ''}',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
              backgroundColor: Colors.blueGrey,
              actions: [
                if (_currentRole == 'Admin')
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
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white, size: 40),
                  onPressed: _handleLogout,
                  tooltip: 'Log Out',
                ),
              ],
            ),
          ),
          drawer: isFacilitySelected ? _buildDrawer() : null,
          body: Row(
            children: [
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

    final role = _currentRole == 'Developer' ? 'Technician' : _currentRole ?? 'User';
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
        };

        final screenBuilder = screenMap[title];
        if (screenBuilder != null) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => screenBuilder()),
          ).then((_) {
            logger.i('Successfully navigated to $title with facilityId: $_selectedFacilityId');
            if (mounted && _messengerKey.currentState != null) {
              _messengerKey.currentState!.showSnackBar(
                SnackBar(
                  content: Text('Navigation to $title successful', style: GoogleFonts.poppins()),
                ),
              );
            }
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
    final role = _currentRole == 'Developer' ? 'Technician' : _currentRole ?? 'User';
    final org = _organization ?? '-';
    final menuItems = _roleMenuItems[role]?[org] ?? _roleMenuItems['User']!['-']!;

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