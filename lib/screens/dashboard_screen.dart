import 'package:cmms/display%20screens/facility_screen.dart';
import 'package:cmms/display%20screens/role_assignment_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/authentication/login_screen.dart';
import 'package:cmms/screens/developer_screen.dart';
import 'package:cmms/screens/schedule_maintenance_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _currentRole = widget.role == 'Unknown' ? 'User' : widget.role;
    _selectedFacilityId = widget.facilityId.isNotEmpty ? widget.facilityId : null;
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
        } else if (developerDoc.exists) {
          _currentRole = 'Developer';
        } else if (technicianDoc.exists || (userDoc.exists && (userDoc.data()?['role'] as String?) == 'Technician')) {
          _currentRole = 'Technician';
        } else {
          _currentRole = 'User';
        }
        logger.i(
          'Initial role set: $_currentRole, TechnicianDoc: ${technicianDoc.exists}, UserRole: ${userDoc.exists ? (userDoc.data()?['role'] as String? ?? 'N/A') : 'N/A'}',
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
            } else {
              _isDeveloper = collection == 'Developers' ? false : _isDeveloper;
              if (!['Admins', 'Developers', 'Technicians']
                  .any((coll) => coll != collection && _currentRole == (coll == 'Admins' ? 'Admin' : coll.replaceAll('s', '')))) {
                FirebaseFirestore.instance.collection('Users').doc(uid).get().then((userDoc) {
                  if (mounted && userDoc.exists && (userDoc.data()?['role'] as String?) == 'Technician') {
                    setState(() {
                      _currentRole = 'Technician';
                    });
                  } else if (mounted) {
                    setState(() {
                      _currentRole = 'User';
                    });
                  }
                  logger.i('Role after snapshot check: $_currentRole');
                });
              }
            }
            logger.i('Snapshot update for $collection, Role: $_currentRole');
          });
        }
      }, onError: (e) {
        logger.e('Error listening to $collection role: $e');
      });
    }

    FirebaseFirestore.instance.collection('Users').doc(uid).snapshots().listen((snapshot) async {
      if (mounted && snapshot.exists) {
        final role = snapshot.data()?['role'] as String? ?? '-';
        if (role == 'Technician' && _currentRole != 'Admin' && _currentRole != 'Developer') {
          setState(() {
            _currentRole = 'Technician';
          });
          logger.i('Users collection updated role to Technician');
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
    });
    logger.i('Selected facility: $facilityId');
  }

  @override
  void dispose() {
    super.dispose();
  }

  final Map<String, List<Map<String, dynamic>>> _roleMenuItems = {
    'Admin': [
      {'title': 'Scheduled Maintenance', 'icon': Icons.event},
      {'title': 'Preventive Maintenance', 'icon': Icons.build_circle},
      {'title': 'Reports', 'icon': Icons.bar_chart},
      {'title': 'Price List', 'icon': Icons.attach_money},
      {'title': 'Requests', 'icon': Icons.request_page},
      {'title': 'Work Orders', 'icon': Icons.work},
      {'title': 'Equipment Supplied', 'icon': Icons.construction},
      {'title': 'Inventory and Parts', 'icon': Icons.inventory},
    ],
    'Technician': [
      {'title': 'Scheduled Maintenance', 'icon': Icons.event},
      {'title': 'Preventive Maintenance', 'icon': Icons.build_circle},
      {'title': 'Reports', 'icon': Icons.bar_chart},
      {'title': 'Price List', 'icon': Icons.attach_money},
      {'title': 'Requests', 'icon': Icons.request_page},
      {'title': 'Work Orders', 'icon': Icons.work},
      {'title': 'Equipment Supplied', 'icon': Icons.construction},
      {'title': 'Inventory and Parts', 'icon': Icons.inventory},
    ],
    'User': [
      {'title': 'Scheduled Maintenance', 'icon': Icons.event},
      {'title': 'Preventive Maintenance', 'icon': Icons.build_circle},
      {'title': 'Reports', 'icon': Icons.bar_chart},
      {'title': 'Price List', 'icon': Icons.attach_money},
      {'title': 'Requests', 'icon': Icons.request_page},
      {'title': 'Work Orders', 'icon': Icons.work},
      {'title': 'Equipment Supplied', 'icon': Icons.construction},
      {'title': 'Inventory and Parts', 'icon': Icons.inventory},
    ],
  };

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTabletOrWeb = screenWidth > 600;
    final displayRole = _currentRole == 'Developer' ? 'Technician' : _currentRole ?? 'User';

    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(80.0),
          child: AppBar(
            leading: isTabletOrWeb
                ? null
                : Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(Icons.menu, color: Colors.white, size: 40),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      tooltip: 'Open Menu',
                    ),
                  ),
            title: Text(
              '$displayRole Dashboard',
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
        drawer: isTabletOrWeb ? null : _buildDrawer(),
        body: Row(
          children: [
            if (isTabletOrWeb) _buildSidebar(),
            Expanded(
              child: FacilityScreen(
                selectedFacilityId: _selectedFacilityId,
                onFacilitySelected: _onFacilitySelected,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          _buildAppIcon(),
          ..._buildMenuItems(),
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
          ..._buildMenuItems(),
        ],
      ),
    );
  }

  List<Widget> _buildMenuItems() {
    final role = _currentRole == 'Developer' ? 'Technician' : _currentRole ?? 'User';
    final menuItems = _roleMenuItems[role] ?? _roleMenuItems['User']!;

    return menuItems.map((item) {
      return ListTile(
        leading: Icon(item['icon'], color: Colors.blueGrey),
        title: Text(item['title'], style: GoogleFonts.poppins()),
        onTap: () {
          if (role == 'User') {
            _messengerKey.currentState?.showSnackBar(
              SnackBar(
                content: Text("Wait for Admin's role assignment to utilize the features", style: GoogleFonts.poppins()),
              ),
            );
          } else {
            if (item['title'] == 'Scheduled Maintenance') {
              if (_selectedFacilityId == null) {
                _messengerKey.currentState?.showSnackBar(
                  SnackBar(
                    content: Text("Please select a facility first", style: GoogleFonts.poppins()),
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ScheduleMaintenanceScreen(
                      facilityId: _selectedFacilityId!,
                      selectedSubSection: 'schedule_maintenance',
                    ),
                  ),
                );
              }
            }
            Navigator.pop(context);
          }
        },
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