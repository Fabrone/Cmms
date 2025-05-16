import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';

class RoleAssignmentScreen extends StatefulWidget {
  const RoleAssignmentScreen({super.key});

  @override
  State<RoleAssignmentScreen> createState() => _RoleAssignmentScreenState();
}

class _RoleAssignmentScreenState extends State<RoleAssignmentScreen> {
  final TextEditingController _uidController = TextEditingController();
  final Logger _logger = Logger();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();

  Future<void> _assignRole(String uid) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          _messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('No authenticated user', style: GoogleFonts.poppins())),
          );
        }
        return;
      }

      // Fetch Admin's organization
      final adminDoc = await FirebaseFirestore.instance.collection('Admins').doc(user.uid).get();
      if (!adminDoc.exists) {
        if (mounted) {
          _messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('Only Admins can assign Technician roles', style: GoogleFonts.poppins())),
          );
        }
        return;
      }
      final adminOrg = adminDoc.data()?['organization'] ?? '-';
      if (adminOrg == '-') {
        if (mounted) {
          _messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('Admin organization not set', style: GoogleFonts.poppins())),
          );
        }
        return;
      }

      final userDoc = await FirebaseFirestore.instance.collection('Users').doc(uid).get();
      if (!userDoc.exists) {
        if (mounted) {
          _messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('User not found', style: GoogleFonts.poppins())),
          );
        }
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      if (userData['role'] != '-') {
        if (mounted) {
          _messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('User already has a role: ${userData['role']}', style: GoogleFonts.poppins())),
          );
        }
        return;
      }

      final roleData = {
        'username': userData['username'] ?? '',
        'email': userData['email'] ?? '',
        'organization': adminOrg,
        'createdAt': Timestamp.now(),
        'isDisabled': false,
      };

      _logger.i('Assigning Technician role to Users/$uid with organization: $adminOrg');
      await FirebaseFirestore.instance.collection('Technicians').doc(uid).set(roleData);
      try {
        _logger.i('Updating Users/$uid/role to Technician');
        await FirebaseFirestore.instance.collection('Users').doc(uid).update({'role': 'Technician'});
      } catch (e) {
        _logger.e('Failed to update role in Users collection: $e');
        if (mounted) {
          _messengerKey.currentState?.showSnackBar(
            SnackBar(
              content: Text('Technician role assigned, but failed to update user role: $e', style: GoogleFonts.poppins()),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      await _logActivity('Assigned Technician role to $uid (User: ${userData['username']}, Organization: $adminOrg)');
      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Technician role assigned successfully!', style: GoogleFonts.poppins())),
        );
        _uidController.clear();
      }
    } catch (e) {
      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error assigning role: $e', style: GoogleFonts.poppins())),
        );
      }
      _logger.e('Error assigning role to Users/$uid: $e');
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
      _logger.e('Error logging activity: $e');
    }
  }

  @override
  void dispose() {
    _uidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 600;

    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Assign Technician Role', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.blueGrey,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select or Enter User to Assign Technician Role',
                  style: GoogleFonts.poppins(
                    fontSize: isMobile ? 18 : 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey[800],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _uidController,
                        decoration: InputDecoration(
                          labelText: 'Enter User UID',
                          hintText: 'e.g., abc123xyz789',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          labelStyle: GoogleFonts.poppins(),
                        ),
                        style: GoogleFonts.poppins(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        if (_uidController.text.isEmpty) {
                          _messengerKey.currentState?.showSnackBar(
                            SnackBar(content: Text('Please enter a User UID', style: GoogleFonts.poppins())),
                          );
                          return;
                        }
                        _assignRole(_uidController.text);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text('Assign', style: GoogleFonts.poppins(color: Colors.white)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Available Users (Unassigned Role)',
                  style: GoogleFonts.poppins(
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.blueGrey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('Users').snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Colors.blueGrey));
                      }
                      if (snapshot.hasError) {
                        _logger.e('Firestore error: ${snapshot.error}');
                        return Center(child: Text('Error: ${snapshot.error}', style: GoogleFonts.poppins(color: Colors.red)));
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Center(child: Text('No users found.', style: GoogleFonts.poppins()));
                      }

                      final users = snapshot.data!.docs
                          .where((doc) => (doc.data() as Map<String, dynamic>)['role'] == '-')
                          .toList();

                      if (users.isEmpty) {
                        return Center(child: Text('No eligible users found.', style: GoogleFonts.poppins()));
                      }

                      return ListView.builder(
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          final user = users[index].data() as Map<String, dynamic>;
                          final uid = users[index].id;
                          return Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            child: ListTile(
                              title: Text(user['username'] ?? 'No Username', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                              subtitle: Text('Email: ${user['email'] ?? 'N/A'}', style: GoogleFonts.poppins()),
                              trailing: ElevatedButton(
                                onPressed: () => _assignRole(uid),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueGrey,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: Text('Assign Technician', style: GoogleFonts.poppins(color: Colors.white)),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}