import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/authentication/registration_screen.dart';
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

  Future<bool> _isDeveloper() async {
    if (FirebaseAuth.instance.currentUser == null) return false;
    DocumentSnapshot developerDoc = await FirebaseFirestore.instance
        .collection('Developers')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .get();
    return developerDoc.exists;
  }

  Future<void> _handleLogout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const RegistrationScreen()),
    );
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
    final displayRole = widget.role == 'Developer' ? 'User' : widget.role;

    return Scaffold(
      appBar: AppBar(
        leading: isTabletOrWeb
            ? null
            : IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
        title: Text(
          displayRole,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.blueGrey,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _handleLogout,
            tooltip: 'Log Out',
          ),
        ],
      ),
      drawer: isTabletOrWeb ? null : _buildDrawer(context),
      body: Row(
        children: [
          if (isTabletOrWeb) _buildSidebar(context),
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
                        if (widget.role == 'MainAdmin') ...[
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

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          _buildAppIcon(context),
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

  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: 250,
      color: Colors.blueGrey[50],
      child: Column(
        children: [
          _buildAppIcon(context),
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

  Widget _buildAppIcon(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isDeveloper(),
      builder: (context, snapshot) {
        bool isDeveloper = snapshot.data ?? false;
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: GestureDetector(
            onTap: isDeveloper
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
              color: isDeveloper ? null : Colors.grey,
            ),
          ),
        );
      },
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