import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';

class UserScreen extends StatefulWidget {
  final String facilityId;

  const UserScreen({super.key, required this.facilityId});

  @override
  State<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  final Logger _logger = Logger();
  final _emailController = TextEditingController();
  String? _selectedRole;
  List<String> _selectedSections = [];
  bool _isLoading = false;
  String? _errorMessage;

  final List<String> _roles = ['jv_admin', 'technician', 'requestor', 'auditor'];
  final List<String> _allSections = [
    'locations',
    'building_survey',
    'drawings',
    'schedule_maintenance',
    'documentations',
    'preventive_maintenance',
    'reports',
    'facility_management',
    'price_list',
    'requests',
    'work_orders',
    'equipment_supplied',
    'inventory',
    'vendors',
    'users',
    'kpis',
  ];

  bool get _isEmbassyAdmin {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    // In production, check Firestore role
    return true; // Temporary for testing
  }

  Future<String?> _getUserUidByEmail(String email) async {
    try {
      // Note: Firebase Admin SDK is needed to lookup UID by email in production
      // For now, assume email is unique and check Firestore for existing user
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        return query.docs.first.id;
      }
      return null;
    } catch (e) {
      _logger.e('Error finding user by email: $e');
      return null;
    }
  }

  Future<void> _assignRole() async {
    if (!_isEmbassyAdmin) {
      setState(() {
        _errorMessage = 'Only Embassy Admin can assign roles';
      });
      return;
    }

    final email = _emailController.text.trim();
    if (email.isEmpty || _selectedRole == null || _selectedSections.isEmpty) {
      setState(() {
        _errorMessage = 'Please fill all fields and select at least one section';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final uid = await _getUserUidByEmail(email);
      if (uid == null) {
        setState(() {
          _errorMessage = 'User not found for email: $email';
        });
        return;
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'email': email,
        'role': _selectedRole,
        'permittedSections': _selectedSections,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));

      _logger.i('Role assigned: $email (UID: $uid) -> $_selectedRole');
      setState(() {
        _emailController.clear();
        _selectedRole = null;
        _selectedSections = [];
      });
    } catch (e) {
      _logger.e('Error assigning role: $e');
      setState(() {
        _errorMessage = 'Error assigning role: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 600;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'User Management',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: isMobile ? 20 : 24,
                ),
              ),
              const SizedBox(height: 16),
              if (_isEmbassyAdmin) ...[
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'User Email',
                    border: const OutlineInputBorder(),
                    errorText: _errorMessage != null && _errorMessage!.contains('email') ? _errorMessage : null,
                  ),
                  style: GoogleFonts.poppins(fontSize: isMobile ? 14 : 16),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(),
                  ),
                  items: _roles.map((role) => DropdownMenuItem(
                        value: role,
                        child: Text(
                          role.replaceAll('_', ' ').toUpperCase(),
                          style: GoogleFonts.poppins(fontSize: isMobile ? 14 : 16),
                        ),
                      )).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedRole = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Permitted Sections',
                  style: GoogleFonts.poppins(
                    fontSize: isMobile ? 14 : 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: _allSections.map((section) => CheckboxListTile(
                          title: Text(
                            section.replaceAll('_', ' ').toUpperCase(),
                            style: GoogleFonts.poppins(fontSize: isMobile ? 12 : 14),
                          ),
                          value: _selectedSections.contains(section),
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                _selectedSections.add(section);
                              } else {
                                _selectedSections.remove(section);
                              }
                            });
                          },
                        )).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                if (_errorMessage != null && !_errorMessage!.contains('email'))
                  Text(
                    _errorMessage!,
                    style: GoogleFonts.poppins(
                      fontSize: isMobile ? 12 : 14,
                      color: Colors.red,
                    ),
                  ),
                const SizedBox(height: 16),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _assignRole,
                        child: Text(
                          'Assign Role',
                          style: GoogleFonts.poppins(
                            fontSize: isMobile ? 14 : 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ] else
                Center(
                  child: Text(
                    'Only Embassy Admin can manage users',
                    style: GoogleFonts.poppins(
                      fontSize: isMobile ? 14 : 16,
                      color: Colors.red,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}