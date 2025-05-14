import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/authentication/login_screen.dart';
import 'package:cmms/screens/developer_screen.dart';
import 'package:logger/logger.dart';

class DashboardScreen extends StatefulWidget {
  final String facilityId;
  final String role; // Developer, Admin, Technician, User

  const DashboardScreen({super.key, required this.facilityId, required this.role});

  @override
  DashboardScreenState createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  final logger = Logger(printer: PrettyPrinter());
  final TextEditingController _uidController = TextEditingController();
  String? _currentRole;
  bool _isDeveloper = false;

  @override
  void initState() {
    super.initState();
    _currentRole = widget.role == 'Unknown' ? 'User' : widget.role;
    _initializeRoleListeners();
  }

  Future<void> _initializeRoleListeners() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _redirectToLogin('No user logged in');
      return;
    }

    logger.i('Initializing role for UID: ${user.uid}');

    // Check initial Developer, Admin, Technician, and Users collection
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

    // Listen to role changes
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
                // Check Users collection for Technician role
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

    // Listen to Users collection for role changes
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

    // Listen to auth state
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error logging out: $e')),
        );
      }
      logger.e('Error logging out: $e');
    }
  }

  Future<void> _assignRole(String uid, String collection) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('Users').doc(uid).get();
      if (!userDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User not found')),
          );
        }
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      if (userData['role'] != '-') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('User already has a role: ${userData['role']}')),
          );
        }
        return;
      }

      final roleData = {
        'username': userData['username'] ?? '',
        'email': userData['email'] ?? '',
        'createdAt': Timestamp.now(),
        'isDisabled': false,
      };

      logger.i('Assigning Technician role to Users/$uid');
      await FirebaseFirestore.instance.collection(collection).doc(uid).set(roleData);
      try {
        logger.i('Updating Users/$uid/role to Technician');
        await FirebaseFirestore.instance.collection('Users').doc(uid).update({'role': 'Technician'});
      } catch (e) {
        logger.e('Failed to update role in Users collection: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Technician role assigned, but failed to update user role: $e'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      await _logActivity('Assigned Technician role to $uid (User: ${userData['username']})');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Technician role assigned successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error assigning role: $e')),
        );
      }
      logger.e('Error assigning role to Users/$uid: $e');
    }
  }

  Future<void> _logActivity(String action) async {
    try {
      await FirebaseFirestore.instance.collection('admin_logs').add({
        'action': action,
        'timestamp': Timestamp.now(),
        'adminUid': FirebaseAuth.instance.currentUser?.uid,
      });
    } catch (e) {
      logger.e('Error logging activity: $e');
    }
  }

  void _showAssignRoleDialog(String collection) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Assign Technician Role', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _uidController,
                decoration: InputDecoration(
                  labelText: 'Enter User UID',
                  hintText: 'e.g., abc123xyz789',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.search, color: Colors.blueGrey),
              onPressed: () => _showUserListDialog(collection),
              tooltip: 'Select User',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (_uidController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a User UID')),
                );
                return;
              }
              _assignRole(_uidController.text, collection);
              Navigator.pop(context);
              _uidController.clear();
            },
            child: const Text('Assign'),
          ),
        ],
      ),
    );
  }

  void _showUserListDialog(String collection) {
    bool isExpanded = false;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Select User', style: TextStyle(fontWeight: FontWeight.bold)),
              IconButton(
                icon: Icon(
                  isExpanded ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: Colors.blueGrey,
                ),
                onPressed: () {
                  setDialogState(() {
                    isExpanded = !isExpanded;
                  });
                },
                tooltip: isExpanded ? 'Reduce Size' : 'Expand to Full Screen',
              ),
            ],
          ),
          content: SizedBox(
            width: isExpanded ? double.maxFinite : 400,
            height: isExpanded ? MediaQuery.of(context).size.height * 0.8 : 300,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('Users').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Text('No users found.');
                }
                final users = snapshot.data!.docs
                    .where((doc) => (doc.data() as Map<String, dynamic>)['role'] == '-')
                    .toList();
                if (users.isEmpty) {
                  return const Text('No eligible users found.');
                }
                return ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index].data() as Map<String, dynamic>;
                    final uid = users[index].id;
                    return ListTile(
                      title: Text(user['username'] ?? 'No Username'),
                      subtitle: Text('Email: ${user['email'] ?? 'N/A'}'),
                      onTap: () {
                        _uidController.text = uid;
                        Navigator.pop(context);
                      },
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _uidController.dispose();
    super.dispose();
  }

  // Define menu items for each role
  final Map<String, List<Map<String, dynamic>>> _roleMenuItems = {
    'Admin': [
      {'title': 'Assign Technician', 'icon': Icons.build},
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
    final contentWidth = screenWidth > 800 ? screenWidth * 0.6 : screenWidth * 0.9;
    final displayRole = _currentRole == 'Developer' ? 'Technician' : _currentRole ?? 'User';

    return Scaffold(
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
            displayRole,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 24,
            ),
          ),
          backgroundColor: Colors.blueGrey,
          actions: [
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
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  child: Container(
                    constraints: BoxConstraints(maxWidth: contentWidth),
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Welcome to Your $displayRole Dashboard',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'This is your centralized hub for managing all aspects of the CMMS application.',
                          style: TextStyle(fontSize: 16, color: Colors.blueGrey),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 30),
                        if (_currentRole == 'Admin')
                          _buildActionCard(
                            title: 'Assign Technician',
                            icon: Icons.build,
                            onTap: () => _showAssignRoleDialog('Technicians'),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(16.0),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _currentRole == 'User'
                                  ? 'Waiting for Admin role assignment.'
                                  : 'Features available based on your role.',
                              style: const TextStyle(fontSize: 16, color: Colors.blueGrey),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
        title: Text(item['title']),
        onTap: () {
          if (role == 'User') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Wait for Admin's role assignment to utilize the features"),
              ),
            );
          } else {
            Navigator.pop(context); // Close drawer for Technician, Admin
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

  Widget _buildActionCard({required String title, required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(icon, size: 40, color: Colors.blueGrey),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}