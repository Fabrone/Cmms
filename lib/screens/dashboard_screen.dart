//import 'package:cmms/display%20screens/locations_screen.dart';
import 'package:cmms/display%20screens/role_assignment_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
//import 'package:cmms/developer/developer_screen.dart';
//import 'package:cmms/display%20screens/billing_screen.dart';
//import 'package:cmms/display%20screens/building_survey_screen.dart';
//import 'package:cmms/display%20screens/documentations_screen.dart';
//import 'package:cmms/display%20screens/drawings_screen.dart';
//import 'package:cmms/display%20screens/equipment_supplied_screen.dart';
import 'package:cmms/display%20screens/facility_screen.dart';
//import 'package:cmms/display%20screens/inventory_screen.dart';
//import 'package:cmms/display%20screens/kpi_screen.dart';
/*import 'package:cmms/display%20screens/price_list_screen.dart';
import 'package:cmms/display%20screens/report_screen.dart';
import 'package:cmms/display%20screens/reports_screen.dart';
import 'package:cmms/display%20screens/request_screen.dart';
import 'package:cmms/display%20screens/schedule_maintenance_screen.dart';
import 'package:cmms/display%20screens/vendor_screen.dart';
import 'package:cmms/display%20screens/work_order_screen.dart';
import 'package:cmms/screens/user_screen.dart';
import 'package:cmms/screens/settings_screen.dart';
import 'package:cmms/technician/preventive_maintenance_screen.dart';*/
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

  // Role-specific menu items - UPDATED to remove Profile, About, Help & Support

  @override
  Widget build(BuildContext context) {
    final displayRole = _currentRole;
    final isFacilitySelected = _selectedFacilityId != null && _selectedFacilityId!.isNotEmpty;

    if (!isFacilitySelected) {
      // When no facility is selected, use simple layout for facility selection
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            _showLogoutConfirmation();
          }
        },
        child: ScaffoldMessenger(
          key: _messengerKey,
          child: Scaffold(
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

    // When facility is selected, use the responsive wrapper
    return ScaffoldMessenger(
      key: _messengerKey,
      child: ResponsiveScreenWrapper(
        title: '$displayRole Dashboard',
        facilityId: _selectedFacilityId!,
        currentRole: _currentRole,
        organization: _organization,
        onFacilityReset: _refreshFacilitiesView,
        actions: [
          // Admin-specific actions
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
    return FacilityScreen(
      selectedFacilityId: _selectedFacilityId,
      onFacilitySelected: _onFacilitySelected,
      isSelectionActive: _isFacilitySelectionActive,
    );
  }
}
