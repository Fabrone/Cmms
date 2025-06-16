import 'package:cmms/display%20screens/role_assignment_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cmms/display%20screens/facility_screen.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'package:logger/logger.dart';
import 'package:cmms/authentication/login_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
  String _organization = '-';
  String? _selectedFacilityId;
  bool _isFacilitySelectionActive = true;
  List<StreamSubscription<DocumentSnapshot>> _roleSubscriptions = [];

  @override
  void initState() {
    super.initState();
    _currentRole = widget.role == 'Unknown' ? 'User' : widget.role;
    _selectedFacilityId = widget.facilityId.isNotEmpty ? widget.facilityId : null;
    _isFacilitySelectionActive = widget.facilityId.isEmpty;
    _checkUserRole();
  }

  @override
  void dispose() {
    for (var subscription in _roleSubscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  Future<void> _checkUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _redirectToLogin('No user logged in');
      return;
    }

    logger.i('Checking roles for user: ${user.uid}');
    for (var subscription in _roleSubscriptions) {
      subscription.cancel();
    }
    _roleSubscriptions = [];

    _setupRoleListener('Admins', user.uid);
    _setupRoleListener('Developers', user.uid);
    _setupRoleListener('Technicians', user.uid);
    _setupRoleListener('Users', user.uid);

    await _updateUserRole(user.uid);
  }

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
      },
    );
    _roleSubscriptions.add(subscription);
  }

  Future<void> _updateUserRole(String uid) async {
    try {
      final adminDoc = await FirebaseFirestore.instance.collection('Admins').doc(uid).get();
      final developerDoc = await FirebaseFirestore.instance.collection('Developers').doc(uid).get();
      final technicianDoc = await FirebaseFirestore.instance.collection('Technicians').doc(uid).get();
      final userDoc = await FirebaseFirestore.instance.collection('Users').doc(uid).get();

      String newRole = 'User';
      String newOrg = '-';

      logger.i('Role documents: Admin=${adminDoc.exists}, Developer=${developerDoc.exists}, Technician=${technicianDoc.exists}, User=${userDoc.exists}');

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

  void _refreshFacilitiesView() {
    setState(() {
      _selectedFacilityId = null;
      _isFacilitySelectionActive = true;
    });
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

  void _handleBackNavigation() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      logger.i('Navigated back to previous screen');
    } else {
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

  @override
  Widget build(BuildContext context) {
    final displayRole = _currentRole;
    final isFacilitySelected = _selectedFacilityId != null && _selectedFacilityId!.isNotEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _showLogoutConfirmation();
        }
      },
      child: ScaffoldMessenger(
        key: _messengerKey,
        child: isFacilitySelected
            ? ResponsiveScreenWrapper(
                title: '$displayRole Dashboard',
                facilityId: _selectedFacilityId!,
                currentRole: _currentRole,
                organization: _organization,
                onFacilityReset: _refreshFacilitiesView,
                actions: [
                  if (_currentRole == 'Admin')
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: IconButton(
                        icon: const Icon(Icons.person_add, color: Colors.white),
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
                child: _buildMainContent(),
              )
            : Scaffold(
                key: _scaffoldKey,
                appBar: AppBar(
                  title: Text(
                    'Select Facility',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 24,
                    ),
                  ),
                  backgroundColor: Colors.blueGrey,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                    onPressed: _handleBackNavigation,
                    tooltip: 'Back',
                  ),
                  elevation: 0,
                ),
                body: _buildMainContent(),
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
            style: GoogleFonts.poppins(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _performLogout();
              },
              child: Text('Logout', style: GoogleFonts.poppins(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performLogout() async {
    if (kIsWeb) {
      logger.i('Performing web-specific logout');
    }
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  Widget _buildMainContent() {
    return FacilityScreen(
      selectedFacilityId: _selectedFacilityId,
      onFacilitySelected: _onFacilitySelected,
      isSelectionActive: _isFacilitySelectionActive,
    );
  }
}