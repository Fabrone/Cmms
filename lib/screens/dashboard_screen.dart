import 'package:cmms/display%20screens/role_assignment_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cmms/display%20screens/facility_screen.dart';
import 'package:cmms/screens/organization_selection_screen.dart'; // 🔧 NEW: Import organization selection screen
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
  bool _isClient = false;
  String? _selectedFacilityId;
  String? _selectedOrganizationId; // 🔧 NEW: Track selected organization
  String? _selectedOrganizationName; // 🔧 NEW: Track selected organization name
  bool _isFacilitySelectionActive = true;
  bool _isOrganizationSelectionActive = false; // 🔧 NEW: Track organization selection state
  List<StreamSubscription<DocumentSnapshot>> _roleSubscriptions = [];
  final List<StreamSubscription<DocumentSnapshot>> _organizationSubscriptions = [];

  @override
  void initState() {
    super.initState();
    _currentRole = widget.role == 'Unknown' ? 'User' : widget.role;
    _selectedFacilityId = widget.facilityId.isNotEmpty ? widget.facilityId : null;
    _isFacilitySelectionActive = widget.facilityId.isEmpty;
    _checkUserRole();
    _setupOrganizationListeners();
  }

  @override
  void dispose() {
    for (var subscription in _roleSubscriptions) {
      subscription.cancel();
    }
    for (var subscription in _organizationSubscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _setupOrganizationListeners() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Clear existing organization subscriptions
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
          logger.i('Organization update detected in Users collection for ${user.uid}');
          _checkClientStatus();
        }
      },
      onError: (error) {
        logger.e('Error in Users organization listener: $error');
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
          logger.i('Organization update detected in Technicians collection for ${user.uid}');
          _checkClientStatus();
        }
      },
      onError: (error) {
        logger.e('Error in Technicians organization listener: $error');
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
        // User is a Technician - check organization from Technicians collection
        orgFromCheck = technicianDoc.data()?['organization'] ?? '-';
        isClient = orgFromCheck != 'JV Almacis';
        logger.i('Technician organization check: $orgFromCheck, isClient: $isClient');
      } else {
        // User is not a Technician - check organization from Users collection
        final userDoc = await FirebaseFirestore.instance
            .collection('Users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          orgFromCheck = userDoc.data()?['organization'] ?? '-';
          isClient = orgFromCheck != 'JV Almacis';
          logger.i('User organization check: $orgFromCheck, isClient: $isClient');
        }
      }

      if (mounted) {
        setState(() {
          _isClient = isClient;
          if (orgFromCheck != '-') {
            _organization = orgFromCheck;
          }
          
          // 🔧 NEW: Set organization selection state based on user type
          if (!isClient && orgFromCheck == 'JV Almacis') {
            // JV Almacis users should select organization first
            _isOrganizationSelectionActive = _selectedOrganizationId == null;
            _isFacilitySelectionActive = _selectedOrganizationId != null && _selectedFacilityId == null;
          } else {
            // Client users go directly to facility selection
            _isOrganizationSelectionActive = false;
            _isFacilitySelectionActive = _selectedFacilityId == null;
            _selectedOrganizationName = orgFromCheck; // Set their organization as selected
          }
        });
        logger.i('Updated client status: isClient=$isClient, org=$orgFromCheck, orgSelection=$_isOrganizationSelectionActive, facilitySelection=$_isFacilitySelectionActive');
      }
    } catch (e) {
      logger.e('Error checking client status: $e');
    }
  }

  Future<void> _checkUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _redirectToLogin('No user logged in');
      return;
    }

    logger.i('Checking roles and organization for user: ${user.uid}');
    for (var subscription in _roleSubscriptions) {
      subscription.cancel();
    }
    _roleSubscriptions = [];

    _setupRoleListener('Admins', user.uid);
    _setupRoleListener('Developers', user.uid);
    _setupRoleListener('Technicians', user.uid);
    _setupRoleListener('Users', user.uid);

    await _updateUserRoleAndOrganization(user.uid);
    await _checkClientStatus();
  }

  void _setupRoleListener(String collection, String uid) {
    final stream = FirebaseFirestore.instance
        .collection(collection)
        .doc(uid)
        .snapshots();
    final subscription = stream.listen(
      (snapshot) {
        logger.i('Role update detected in $collection for $uid');
        _updateUserRoleAndOrganization(uid);
        _checkClientStatus();
      },
      onError: (error) {
        logger.e('Error in $collection listener: $error');
      },
    );
    _roleSubscriptions.add(subscription);
  }

  Future<void> _updateUserRoleAndOrganization(String uid) async {
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
        newOrg = adminDoc.data()?['organization'] ?? '-';
      } else if (developerDoc.exists) {
        newRole = 'Technician'; // Display as Technician but maintain Developer privileges
        newOrg = 'JV Almacis';
      } else if (technicianDoc.exists) {
        newRole = 'Technician';
        newOrg = technicianDoc.data()?['organization'] ?? '-';
      } else if (userDoc.exists) {
        final userData = userDoc.data();
        newRole = userData?['role'] ?? 'User';
        newOrg = userData?['organization'] ?? '-';
      }

      // Update Users collection if organization or role is missing or incorrect
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        if (userData['organization'] == null || userData['organization'] != newOrg || userData['role'] != newRole) {
          try {
            await FirebaseFirestore.instance.collection('Users').doc(uid).set({
              'id': uid,
              'username': userData['username'] ?? '',
              'email': userData['email'] ?? '',
              'createdAt': userData['createdAt'] ?? Timestamp.now(),
              'role': newRole,
              'organization': newOrg,
            }, SetOptions(merge: true)).then((_) {
              logger.i('Updated Users collection for $uid: role=$newRole, organization=$newOrg');
            }).catchError((e) {
              logger.e('Failed to update Users collection for $uid: $e');
            });
          } catch (e) {
            logger.e('Error updating Users collection for $uid: $e');
          }
        }
      }

      if (mounted) {
        setState(() {
          _currentRole = newRole;
          _organization = newOrg;
        });
        
        // Silent role switching - removed snackbar message
        logger.i('Role updated silently: $_currentRole${_organization != '-' ? ' ($_organization)' : ''} - ${_isClient ? 'Client' : 'Service Provider'}');
      }
    } catch (e) {
      logger.e('Error updating user role and organization: $e');
      if (mounted) {
        setState(() {
          _currentRole = 'User';
          _organization = '-';
          _isClient = false;
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

  // 🔧 NEW: Handle organization selection
  void _onOrganizationSelected(String organizationId, String organizationName) {
    setState(() {
      _selectedOrganizationId = organizationId;
      _selectedOrganizationName = organizationName;
      _isOrganizationSelectionActive = false;
      _isFacilitySelectionActive = true;
    });
    logger.i('Selected organization: $organizationName (ID: $organizationId)');
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
      // 🔧 NEW: For JV Almacis users, also reset organization selection
      if (!_isClient && _organization == 'JV Almacis') {
        _selectedOrganizationId = null;
        _selectedOrganizationName = null;
        _isOrganizationSelectionActive = true;
        _isFacilitySelectionActive = false;
      }
    });
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          _isClient ? 'Facilities refreshed' : 'Selection refreshed',
          style: GoogleFonts.poppins(),
        ),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.blueGrey[600],
      ),
    );
    logger.i('Selection view refreshed - showing ${_isClient ? 'facility' : 'organization'} selection interface');
  }

  void _handleBackNavigation() {
    // 🔧 NEW: Handle back navigation for organization selection
    if (_isOrganizationSelectionActive) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
        logger.i('Navigated back to previous screen from organization selection');
      } else {
        _showLogoutConfirmation();
      }
    } else if (_isFacilitySelectionActive && !_isClient && _selectedOrganizationId != null) {
      // Go back to organization selection for JV Almacis users
      setState(() {
        _selectedOrganizationId = null;
        _selectedOrganizationName = null;
        _isOrganizationSelectionActive = true;
        _isFacilitySelectionActive = false;
      });
      logger.i('Navigated back to organization selection');
    } else if (Navigator.canPop(context)) {
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
                title: displayRole == '-' ? 'Dashboard' : '$displayRole Dashboard',
                facilityId: _selectedFacilityId!,
                currentRole: _currentRole,
                organization: _organization,
                selectedOrganizationName: _selectedOrganizationName,
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
                    _isOrganizationSelectionActive ? 'Select Organization' : 'Select Facility',
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
    // 🔧 NEW: Show organization selection for JV Almacis users
    if (_isOrganizationSelectionActive) {
      return OrganizationSelectionScreen(
        onOrganizationSelected: _onOrganizationSelected,
      );
    }
    
    // Show facility selection
    return FacilityScreen(
      selectedFacilityId: _selectedFacilityId,
      onFacilitySelected: _onFacilitySelected,
      isSelectionActive: _isFacilitySelectionActive,
      userOrganization: _isClient ? _organization : _selectedOrganizationName, 
      isServiceProvider: !_isClient, 
    );
  }
}