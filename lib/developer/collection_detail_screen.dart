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
        logger.e('User $uid not found in Users collection');
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      if (userData['role'] != '-') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('User already has a role: ${userData['role']}')),
          );
        }
        logger.w('User $uid already has role: ${userData['role']}');
        return;
      }

      final doc = await _firestore.collection(collection).doc(uid).get();
      if (doc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Role already assigned')),
          );
        }
        logger.w('Role already assigned for user $uid in $collection');
        return;
      }

      String organization = '-';
      
      // Determine organization based on collection and current user
      if (collection == 'Technicians') {
        final currentUser = _auth.currentUser;
        if (currentUser != null) {
          final adminDoc = await _firestore.collection('Admins').doc(currentUser.uid).get();
          if (adminDoc.exists) {
            organization = adminDoc.data()!['organization'] ?? '-';
            logger.i('Inherited organization for Technician: $organization');
          } else {
            // If assigning user is not an admin, check if they're a developer
            final developerDoc = await _firestore.collection('Developers').doc(currentUser.uid).get();
            if (developerDoc.exists) {
              // For developers, use selected organization or default
              organization = _selectedOrganization ?? 'JV Almacis';
              logger.i('Developer assigned organization for Technician: $organization');
            } else {
              logger.w('Current user ${currentUser.uid} is neither Admin nor Developer');
              organization = _selectedOrganization ?? '-';
            }
          }
        } else {
          logger.w('No current user logged in for Technician role assignment');
          organization = _selectedOrganization ?? '-';
        }
      } else if (collection == 'Developers') {
        organization = 'JV Almacis';
        logger.i('Set organization for Developer: $organization');
      } else if (collection == 'Admins') {
        organization = _selectedOrganization ?? '-';
        logger.i('Set organization for Admin: $organization');
      }

      // Validate organization for Admins and Technicians
      if ((collection == 'Admins' || collection == 'Technicians') && organization == '-') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select an organization')),
          );
        }
        logger.w('No organization selected for $collection role assignment');
        return;
      }

      final roleData = {
        'username': userData['username'] ?? '',
        'email': userData['email'] ?? '',
        'organization': organization,
        'createdAt': Timestamp.now(),
        'isDisabled': false,
      };

      // Use batch write to ensure both operations succeed or fail together
      final batch = _firestore.batch();
      
      // Add to role collection
      batch.set(_firestore.collection(collection).doc(uid), roleData);
      
      // Update Users collection
      batch.set(_firestore.collection('Users').doc(uid), {
        'id': uid,
        'username': userData['username'] ?? '',
        'email': userData['email'] ?? '',
        'createdAt': userData['createdAt'] ?? Timestamp.now(),
        'role': role,
        'organization': organization,
      }, SetOptions(merge: true));

      await batch.commit();
      
      logger.i('Successfully assigned $role role to user $uid with organization: $organization');

      await _logActivity('Assigned $role role to $uid (User: ${userData['username']}, Organization: $organization)');
      
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

  Future<void> _removeUser(String uid, String username, String collection) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Removal'),
        content: Text('Are you sure you want to remove $username from $collection?'),
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
      if (collection == 'Developers' && (await _firestore.collection('Developers').doc(uid).get()).data()?['email'] == 'lubangafabron@gmail.com') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This is the creator, you can\'t remove him from this role')),
          );
        }
        return;
      }

      // Use batch write for consistency
      final batch = _firestore.batch();
      
      // Remove from role collection
      batch.delete(_firestore.collection(collection).doc(uid));
      
      // Update Users collection (except for admin_logs)
      if (collection != 'admin_logs') {
        batch.set(_firestore.collection('Users').doc(uid), {
          'role': '-',
          'organization': '-',
        }, SetOptions(merge: true));
      }

      await batch.commit();
      
      logger.i('Successfully removed user $uid from $collection collection');

      await _logActivity('Removed $collection entry for $uid (User: $username)');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$collection entry removed successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing $collection entry: $e')),
        );
      }
      logger.e('Error removing $collection entry: $e');
    }
  }

  Future<void> _editUser(String uid, Map<String, dynamic> currentData, String collection) async {
    _usernameController.text = currentData['username'] ?? '';
    _emailController.text = currentData['email'] ?? '';
    
    // Fix: Handle organization value that might not be in dropdown options
    String currentOrg = currentData['organization'] ?? '-';
    List<String> orgOptions = ['Embassy', 'JV Almacis'];
    
    // If current organization is not in the options and it's not '-', add it temporarily
    // or set to null to show no selection
    if (currentOrg == '-' || !orgOptions.contains(currentOrg)) {
      _selectedOrganization = null; // This will show the hint text
    } else {
      _selectedOrganization = currentOrg;
    }

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit $collection Entry', style: const TextStyle(fontWeight: FontWeight.bold)),
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
                if (collection != 'Developers') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedOrganization,
                    decoration: InputDecoration(
                      labelText: 'Organization',
                      hintText: currentOrg == '-' ? 'Select Organization' : 'Current: $currentOrg',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: orgOptions.map((String org) {
                      return DropdownMenuItem<String>(
                        value: org,
                        child: Text(org),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        _selectedOrganization = value;
                      });
                    },
                    validator: (value) {
                      if (collection == 'Admins' || collection == 'Technicians') {
                        return value == null ? 'Please select an organization' : null;
                      }
                      return null;
                    },
                  ),
                ],
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
      ),
    );

    if (confirm != true) return;

    try {
      // Validate organization selection for required collections
      if ((collection == 'Admins' || collection == 'Technicians') && _selectedOrganization == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select an organization')),
          );
        }
        return;
      }

      final updatedOrganization = collection == 'Developers' 
          ? 'JV Almacis' 
          : _selectedOrganization ?? currentOrg; // Keep current if none selected
      
      final updatedData = {
        'username': _usernameController.text.trim(),
        'email': _emailController.text.trim(),
        'organization': updatedOrganization,
        'createdAt': currentData['createdAt'] ?? Timestamp.now(),
        'isDisabled': currentData['isDisabled'] ?? false,
      };

      // Use batch write for consistency
      final batch = _firestore.batch();
      
      // Update role collection
      batch.set(_firestore.collection(collection).doc(uid), updatedData, SetOptions(merge: true));
      
      // Update Users collection
      batch.set(_firestore.collection('Users').doc(uid), {
        'username': _usernameController.text.trim(),
        'email': _emailController.text.trim(),
        'organization': updatedOrganization,
      }, SetOptions(merge: true));

      await batch.commit();
      
      logger.i('Successfully updated $collection and Users collection for $uid: organization=$updatedOrganization');

      await _logActivity('Edited $collection $uid (User: ${updatedData['username']}, Organization: ${updatedData['organization']})');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$collection entry updated successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating $collection entry: $e')),
        );
      }
      logger.e('Error updating $collection entry: $e');
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

  Future<void> _toggleDisableUser(String uid, String username, bool currentStatus, String collection) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(currentStatus ? 'Enable User' : 'Disable User'),
        content: Text(
          currentStatus
              ? 'Are you sure you want to enable $username in $collection?'
              : 'Are you sure you want to disable $username in $collection?',
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
      await _firestore.collection(collection).doc(uid).set({
        'isDisabled': !currentStatus,
      }, SetOptions(merge: true));
      await _logActivity('${currentStatus ? 'Enabled' : 'Disabled'} $collection $uid (User: $username)');
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

  Future<void> _deleteAdminLog(String logId) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: const Text('Are you sure you want to delete this admin log entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _firestore.collection('admin_logs').doc(logId).delete();
      await _logActivity('Deleted admin log entry $logId');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admin log entry deleted successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting admin log: $e')),
        );
      }
      logger.e('Error deleting admin log: $e');
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
    _selectedOrganization = null;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                if (collection == 'Admins' || collection == 'Technicians') ...[
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
                      setDialogState(() {
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
                final docId = doc.id;

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
                                  if (widget.collectionName == 'admin_logs') {
                                    _deleteAdminLog(docId);
                                  } else {
                                    _removeUser(docId, data['username'] ?? 'Unknown', widget.collectionName);
                                  }
                                } else if (value == 'edit' && widget.collectionName != 'admin_logs') {
                                  _editUser(docId, data, widget.collectionName);
                                } else if (value == 'reset' && widget.collectionName != 'admin_logs') {
                                  _resetPassword(data['email']);
                                } else if (value == 'disable' && widget.collectionName != 'admin_logs') {
                                  _toggleDisableUser(
                                      docId, data['username'] ?? 'Unknown', data['isDisabled'] ?? false, widget.collectionName);
                                }
                              },
                              itemBuilder: (context) => [
                                if (widget.collectionName != 'admin_logs') ...[
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, color: Colors.blueGrey),
                                        SizedBox(width: 8),
                                        Text('Edit'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'remove',
                                    child: Row(
                                      children: [
                                        const Icon(Icons.delete, color: Colors.red),
                                        const SizedBox(width: 8),
                                        Text('Remove from ${widget.collectionName}'),
                                      ],
                                    ),
                                  ),
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
                                ] else ...[
                                  const PopupMenuItem(
                                    value: 'remove',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Delete Log'),
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
      floatingActionButton: (widget.collectionName == 'Admins' ||
              widget.collectionName == 'Developers' ||
              widget.collectionName == 'Technicians')
          ? FloatingActionButton(
              onPressed: () => _showAssignRoleDialog(
                widget.collectionName,
                widget.collectionName == 'Admins'
                    ? 'Admin'
                    : widget.collectionName == 'Technicians'
                        ? 'Technician'
                        : 'Developer',
              ),
              backgroundColor: Colors.blueGrey,
              tooltip: 'Assign ${widget.collectionName == 'Admins' ? 'Admin' : widget.collectionName == 'Technicians' ? 'Technician' : 'Developer'}',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}