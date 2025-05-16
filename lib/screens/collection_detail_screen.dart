import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:intl/intl.dart';

class CollectionDetailScreen extends StatefulWidget {
  final String collectionName;
  final List<String> fields;
  final bool hasActions;

  const CollectionDetailScreen({
    super.key,
    required this.collectionName,
    required this.fields,
    required this.hasActions,
  });

  @override
  CollectionDetailScreenState createState() => CollectionDetailScreenState();
}

class CollectionDetailScreenState extends State<CollectionDetailScreen> {
  final logger = Logger(printer: PrettyPrinter());
  final TextEditingController _uidController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _selectedOrganization;

  Future<void> _assignRole(String uid, String collection, String role) async {
    try {
      final userDoc = await _firestore.collection('Users').doc(uid).get();
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

      final doc = await _firestore.collection(collection).doc(uid).get();
      if (doc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Role already assigned')),
          );
        }
        return;
      }

      if (collection == 'Admins' && _selectedOrganization == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select an organization')),
          );
        }
        return;
      }

      final roleData = {
        'username': userData['username'] ?? '',
        'email': userData['email'] ?? '',
        'organization': collection == 'Admins' ? _selectedOrganization : null,
        'createdAt': Timestamp.now(),
        'isDisabled': false,
      };

      // Write to role collection
      await _firestore.collection(collection).doc(uid).set(roleData);
      logger.i('Successfully added user $uid to $collection collection');

      // Update Users collection with role
      try {
        await _firestore.collection('Users').doc(uid).update({'role': role});
        logger.i('Successfully updated role to $role for user $uid in Users collection');
      } catch (e) {
        logger.e('Failed to update role in Users collection: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$role role assigned to $collection, but failed to update user role: $e'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Log the activity
      await _logActivity('Assigned $role role to $uid (User: ${userData['username']}, Organization: ${_selectedOrganization ?? '-'})');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$role role assigned successfully!')),
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

  Future<void> _removeAdmin(String uid, String username) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Removal'),
        content: Text('Are you sure you want to remove $username from Admins?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Delete from Admins collection
      await _firestore.collection('Admins').doc(uid).delete();
      logger.i('Successfully removed user $uid from Admins collection');

      // Update Users collection to remove role
      try {
        await _firestore.collection('Users').doc(uid).update({'role': '-'});
        logger.i('Successfully reset role for user $uid in Users collection');
      } catch (e) {
        logger.e('Failed to reset role in Users collection: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Admin removed, but failed to update user role: $e'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Log the activity
      await _logActivity('Removed Admin role from $uid (User: $username)');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admin removed successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing admin: $e')),
        );
      }
      logger.e('Error removing admin: $e');
    }
  }

  Future<void> _removeDeveloper(String uid, String username, String email) async {
    if (email == 'lubangafabron@gmail.com') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This is the creator, you can’t remove him from this role')),
        );
      }
      return;
    }

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Removal'),
        content: Text('Are you sure you want to remove $username from Developers?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Delete from Developers collection
      await _firestore.collection('Developers').doc(uid).delete();
      logger.i('Successfully removed user $uid from Developers collection');

      // Update Users collection to remove role
      try {
        await _firestore.collection('Users').doc(uid).update({'role': '-'});
        logger.i('Successfully reset role for user $uid in Users collection');
      } catch (e) {
        logger.e('Failed to reset role in Users collection: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Developer removed, but failed to update user role: $e'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Log the activity
      await _logActivity('Removed Developer role from $uid (User: $username)');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Developer removed successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing developer: $e')),
        );
      }
      logger.e('Error removing developer: $e');
    }
  }

  Future<void> _editAdmin(String uid, Map<String, dynamic> currentData) async {
    _usernameController.text = currentData['username'] ?? '';
    _emailController.text = currentData['email'] ?? '';
    _selectedOrganization = currentData['organization'];

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Admin', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedOrganization,
                decoration: InputDecoration(
                  labelText: 'Organization',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: ['Embassy', 'JV Almacis'].map((String org) {
                  return DropdownMenuItem<String>(
                    value: org,
                    child: Text(org),
                  );
                }).toList(),
                onChanged: (value) {
                  _selectedOrganization = value;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final updatedData = {
        'username': _usernameController.text.trim(),
        'email': _emailController.text.trim(),
        'organization': _selectedOrganization,
        'createdAt': currentData['createdAt'],
        'isDisabled': currentData['isDisabled'] ?? false,
      };

      await _firestore.collection('Admins').doc(uid).update(updatedData);
      await _logActivity('Edited Admin $uid (User: ${updatedData['username']}, Organization: ${_selectedOrganization ?? '-'})');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admin updated successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating admin: $e')),
        );
      }
      logger.e('Error updating admin: $e');
    }
  }

  Future<void> _resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      await _logActivity('Sent password reset email to $email');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending password reset: $e')),
        );
      }
      logger.e('Error sending password reset: $e');
    }
  }

  Future<void> _toggleDisableUser(String uid, String username, bool currentStatus) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(currentStatus ? 'Enable User' : 'Disable User'),
        content: Text(
          currentStatus
              ? 'Are you sure you want to enable $username?'
              : 'Are you sure you want to disable $username?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(currentStatus ? 'Enable' : 'Disable'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _firestore.collection('Admins').doc(uid).update({'isDisabled': !currentStatus});
      await _logActivity(
          '${currentStatus ? 'Enabled' : 'Disabled'} Admin $uid (User: $username)');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User ${currentStatus ? 'enabled' : 'disabled'} successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error toggling user status: $e')),
        );
      }
      logger.e('Error toggling user status: $e');
    }
  }

  Future<void> _logActivity(String action) async {
    try {
      await _firestore.collection('admin_logs').add({
        'action': action,
        'timestamp': Timestamp.now(),
        'developerUid': _auth.currentUser?.uid,
      });
    } catch (e) {
      logger.e('Error logging activity: $e');
    }
  }

  void _showAssignRoleDialog(String collection, String role) {
    _selectedOrganization = null; // Reset organization
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Assign $role Role', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
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
                    onPressed: () => _showUserListDialog(collection, role),
                    tooltip: 'Select User',
                  ),
                ],
              ),
              if (collection == 'Admins') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedOrganization,
                  decoration: InputDecoration(
                    labelText: 'Organization',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: ['Embassy', 'JV Almacis'].map((String org) {
                    return DropdownMenuItem<String>(
                      value: org,
                      child: Text(org),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedOrganization = value;
                    });
                  },
                  validator: (value) => value == null ? 'Please select an organization' : null,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (_uidController.text.isEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a UID')),
                  );
                }
                return;
              }
              _assignRole(_uidController.text, collection, role);
              Navigator.pop(context);
              _uidController.clear();
            },
            child: const Text('Assign'),
          ),
        ],
      ),
    );
  }

  void _showUserListDialog(String collection, String role) {
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
              stream: _firestore.collection('Users').snapshots(),
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
                      subtitle: Text('Email: ${user['email'] ?? '-'}'),
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
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.collectionName} Details',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.blueGrey,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection(widget.collectionName).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No data found.'));
          }

          final docs = snapshot.data!.docs;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                ...widget.fields.map((field) => DataColumn(
                      label: Text(
                        field == 'performedBy'
                            ? 'Performed By'
                            : field[0].toUpperCase() + field.substring(1),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    )),
                if (widget.hasActions) const DataColumn(label: Text('Actions')),
              ],
              rows: docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final uid = doc.id;

                return DataRow(cells: [
                  ...widget.fields.map((field) {
                    if (field == 'createdAt' && data[field] != null) {
                      final timestamp = (data[field] as Timestamp).toDate();
                      return DataCell(
                          Text(DateFormat('MMM d, yyyy, h:mm a').format(timestamp)));
                    } else if (field == 'isDisabled') {
                      return DataCell(Text(data[field] == true ? 'Disabled' : 'Enabled'));
                    } else if (field == 'role') {
                      return DataCell(Text(data[field] ?? '-'));
                    } else if (field == 'performedBy') {
                      final developerUid = data['developerUid'];
                      final adminUid = data['mainAdminUid'];
                      return DataCell(
                          Text(developerUid ?? adminUid ?? 'Unknown'));
                    } else if (field == 'organization') {
                      return DataCell(Text(data[field]?.toString() ?? '-'));
                    }
                    return DataCell(Text(data[field]?.toString() ?? '-'));
                  }),
                  if (widget.hasActions)
                    DataCell(
                      widget.collectionName == 'Developers' &&
                              data['email'] == 'lubangafabron@gmail.com'
                          ? const SizedBox.shrink()
                          : PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert),
                              onSelected: (value) {
                                if (value == 'remove') {
                                  if (widget.collectionName == 'Admins') {
                                    _removeAdmin(uid, data['username']);
                                  } else {
                                    _removeDeveloper(
                                        uid, data['username'], data['email']);
                                  }
                                } else if (value == 'edit' && widget.collectionName == 'Admins') {
                                  _editAdmin(uid, data);
                                } else if (value == 'reset') {
                                  _resetPassword(data['email']);
                                } else if (value == 'disable') {
                                  _toggleDisableUser(
                                      uid, data['username'], data['isDisabled'] ?? false);
                                }
                              },
                              itemBuilder: (context) => [
                                if (widget.collectionName == 'Admins') ...[
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, color: Colors.blueGrey),
                                        SizedBox(width: 8),
                                        Text('Edit Admin'),
                                      ],
                                    ),
                                  ),
                                ],
                                PopupMenuItem(
                                  value: 'remove',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.delete, color: Colors.red),
                                      const SizedBox(width: 8),
                                      Text(widget.collectionName == 'Admins'
                                          ? 'Remove Admin'
                                          : 'Remove Developer'),
                                    ],
                                  ),
                                ),
                                if (widget.collectionName == 'Admins') ...[
                                  const PopupMenuItem(
                                    value: 'reset',
                                    child: Row(
                                      children: [
                                        Icon(Icons.lock_reset, color: Colors.blueGrey),
                                        SizedBox(width: 8),
                                        Text('Reset Password'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'disable',
                                    child: Row(
                                      children: [
                                        Icon(
                                          data['isDisabled'] == true
                                              ? Icons.check_circle
                                              : Icons.block,
                                          color: Colors.blueGrey,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(data['isDisabled'] == true
                                            ? 'Enable User'
                                            : 'Disable User'),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    ),
                ]);
              }).toList(),
            ),
          );
        },
      ),
      floatingActionButton: widget.collectionName == 'Admins' ||
              widget.collectionName == 'Developers'
          ? FloatingActionButton(
              onPressed: () => _showAssignRoleDialog(
                widget.collectionName,
                widget.collectionName == 'Admins' ? 'Admin' : 'Developer',
              ),
              backgroundColor: Colors.blueGrey,
              tooltip: 'Assign ${widget.collectionName == 'Admins' ? 'Admin' : 'Developer'}',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}