import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/authentication/login_screen.dart';
import 'package:cmms/screens/developer_screen.dart';
import 'package:logger/logger.dart';

class DashboardScreen extends StatefulWidget {
  final String facilityId;
  final String role; // Developer, MainAdmin, Senior FM Manager, Technician, Requester, Auditor/Inspector

  const DashboardScreen({super.key, required this.facilityId, required this.role});

  @override
  DashboardScreenState createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  final logger = Logger(printer: PrettyPrinter());
  final TextEditingController _uidController = TextEditingController();
  final TextEditingController _seniorFMManagerUidController = TextEditingController();
  String? _currentRole;
  bool _isDeveloper = false;

  @override
  void initState() {
    super.initState();
    _currentRole = widget.role;
    _initializeRoleListeners();
  }

  Future<void> _initializeRoleListeners() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _redirectToLogin('No user logged in');
      return;
    }

    // Check initial Developer status
    final developerDoc = await FirebaseFirestore.instance
        .collection('Developers')
        .doc(user.uid)
        .get();
    if (mounted) {
      setState(() {
        _isDeveloper = developerDoc.exists;
      });
    }

    // Listen to role changes
    _listenToRoleChanges(user.uid);
  }

  void _listenToRoleChanges(String uid) {
    // Role collections
    const roleCollections = [
      'MainAdmins',
      'SeniorFMManagers',
      'Technicians',
      'Requesters',
      'AuditorsInspectors',
      'Developers'
    ];

    for (String collection in roleCollections) {
      FirebaseFirestore.instance
          .collection(collection)
          .doc(uid)
          .snapshots()
          .listen((snapshot) {
        if (mounted) {
          setState(() {
            if (snapshot.exists) {
              _currentRole = collection == 'Developers' ? 'Developer' : collection.replaceAll('s', '');
              if (collection == 'Developers') {
                _isDeveloper = true;
              }
            } else if (collection == 'Developers') {
              _isDeveloper = false;
            }
          });
        }
      }, onError: (e) => logger.e('Error listening to $collection role: $e'));
    }

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

  Future<void> _assignRole(String uid, String collection, {String? seniorFMManagerUid}) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('Users').doc(uid).get();
      if (!userDoc.exists) throw 'User not found';

      final userData = userDoc.data() as Map<String, dynamic>;
      final roleData = {
        'username': userData['username'] ?? '',
        'email': userData['email'] ?? '',
        'createdAt': Timestamp.now(),
        'isDisabled': false,
        if (seniorFMManagerUid != null) 'seniorFMManagerUid': seniorFMManagerUid,
      };

      await FirebaseFirestore.instance.collection(collection).doc(uid).set(roleData);
      await _logActivity('Assigned $collection role to $uid (User: ${userData['username']})');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${collection.replaceAll('s', '')} role assigned successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error assigning role: $e')),
        );
      }
      logger.e('Error assigning role: $e');
    }
  }

  Future<void> _logActivity(String action) async {
    try {
      await FirebaseFirestore.instance.collection('admin_logs').add({
        'action': action,
        'timestamp': Timestamp.now(),
        'mainAdminUid': FirebaseAuth.instance.currentUser?.uid,
      });
    } catch (e) {
      logger.e('Error logging activity: $e');
    }
  }

  void _showAssignRoleDialog(String collection) {
    bool isLowerLevelRole = ['Technicians', 'Requesters', 'AuditorsInspectors'].contains(collection);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Assign ${collection.replaceAll('s', '')} Role', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
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
            if (isLowerLevelRole) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _seniorFMManagerUidController,
                      decoration: InputDecoration(
                        labelText: 'Senior FM Manager UID',
                        hintText: 'e.g., xyz789abc123',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search, color: Colors.blueGrey),
                    onPressed: () => _showSeniorFMManagerListDialog(),
                    tooltip: 'Select Senior FM Manager',
                  ),
                ],
              ),
            ],
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
              if (isLowerLevelRole && _seniorFMManagerUidController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a Senior FM Manager UID')),
                );
                return;
              }
              _assignRole(
                _uidController.text,
                collection,
                seniorFMManagerUid: isLowerLevelRole ? _seniorFMManagerUidController.text : null,
              );
              Navigator.pop(context);
              _uidController.clear();
              _seniorFMManagerUidController.clear();
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
                final users = snapshot.data!.docs;
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

  void _showSeniorFMManagerListDialog() {
    bool isExpanded = false;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Select Senior FM Manager', style: TextStyle(fontWeight: FontWeight.bold)),
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
              stream: FirebaseFirestore.instance.collection('SeniorFMManagers').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Text('No Senior FM Managers found.');
                }
                final managers = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: managers.length,
                  itemBuilder: (context, index) {
                    final manager = managers[index].data() as Map<String, dynamic>;
                    final uid = managers[index].id;
                    return ListTile(
                      title: Text(manager['username'] ?? 'No Username'),
                      subtitle: Text('Email: ${manager['email'] ?? 'N/A'}'),
                      onTap: () {
                        _seniorFMManagerUidController.text = uid;
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
    _seniorFMManagerUidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTabletOrWeb = screenWidth > 600;
    final contentWidth = screenWidth > 800 ? screenWidth * 0.6 : screenWidth * 0.9;
    final displayRole = _currentRole == 'Developer' ? 'User' : (_currentRole ?? 'User');

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80.0), // Increased AppBar height
        child: AppBar(
          leading: isTabletOrWeb
              ? null
              : Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white, size: 40), // Larger menu icon
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    tooltip: 'Open Menu',
                  ),
                ),
          title: Text(
            displayRole,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 24, // Larger font size
            ),
          ),
          backgroundColor: Colors.blueGrey,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white, size: 40), // Larger logout icon
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
                          'This is your centralized hub for managing all aspects of the CMMS application. Additional features will be added as roles and permissions are defined.',
                          style: TextStyle(fontSize: 16, color: Colors.blueGrey),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 30),
                        if (_currentRole == 'MainAdmin') ...[
                          _buildActionCard(
                            title: 'Assign Senior FM Manager',
                            icon: Icons.supervisor_account,
                            onTap: () => _showAssignRoleDialog('SeniorFMManagers'),
                          ),
                          _buildActionCard(
                            title: 'Assign Technician',
                            icon: Icons.build,
                            onTap: () => _showAssignRoleDialog('Technicians'),
                          ),
                          _buildActionCard(
                            title: 'Assign Requester',
                            icon: Icons.request_page,
                            onTap: () => _showAssignRoleDialog('Requesters'),
                          ),
                          _buildActionCard(
                            title: 'Assign Auditor/Inspector',
                            icon: Icons.visibility,
                            onTap: () => _showAssignRoleDialog('AuditorsInspectors'),
                          ),
                        ] else
                          Container(
                            padding: const EdgeInsets.all(16.0),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Features coming soon...',
                              style: TextStyle(fontSize: 16, color: Colors.blueGrey),
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
          ListTile(
            leading: const Icon(Icons.apartment, color: Colors.blueGrey),
            title: const Text('Facilities'),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.location_on, color: Colors.blueGrey),
            title: const Text('Locations'),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.assessment, color: Colors.blueGrey),
            title: const Text('Building Survey'),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.event, color: Colors.blueGrey),
            title: const Text('Schedule Maintenance'),
            onTap: () {
              Navigator.pop(context);
            },
          ),
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
          ListTile(
            leading: const Icon(Icons.apartment, color: Colors.blueGrey),
            title: const Text('Facilities'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.location_on, color: Colors.blueGrey),
            title: const Text('Locations'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.assessment, color: Colors.blueGrey),
            title: const Text('Building Survey'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.event, color: Colors.blueGrey),
            title: const Text('Schedule Maintenance'),
            onTap: () {},
          ),
        ],
      ),
    );
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
          color: _isDeveloper ? null : Colors.grey,
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