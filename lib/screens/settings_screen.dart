import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/screens/profile_screen.dart';
import 'package:cmms/screens/about_screen.dart';
import 'package:cmms/screens/help_support_screen.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'package:cmms/services/notification_service.dart';
import 'package:logger/logger.dart';

class SettingsScreen extends StatefulWidget {
  final String facilityId;
  
  const SettingsScreen({super.key, required this.facilityId});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  final NotificationService _notificationService = NotificationService();
  
  bool _notificationsEnabled = true;
  bool _emailNotifications = true;
  bool _pushNotifications = true;
  String _selectedTheme = 'System';
  String _selectedLanguage = 'English';
  bool _isLoadingNotifications = true;
  
  String _currentRole = 'User';
  String _organization = '-';

  @override
  void initState() {
    super.initState();
    _getCurrentUserRole();
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    try {
      final enabled = await _notificationService.areNotificationsEnabled();
      if (mounted) {
        setState(() {
          _notificationsEnabled = enabled;
          _isLoadingNotifications = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingNotifications = false;
        });
      }
    }
  }

  Future<void> _updateNotificationSettings(bool enabled) async {
    try {
      await _notificationService.setNotificationsEnabled(enabled);
      if (mounted) {
        setState(() {
          _notificationsEnabled = enabled;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled 
                  ? 'Notifications enabled successfully' 
                  : 'Notifications disabled successfully',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: enabled ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error updating notification settings: $e',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _getCurrentUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final adminDoc = await FirebaseFirestore.instance.collection('Admins').doc(user.uid).get();
      final developerDoc = await FirebaseFirestore.instance.collection('Developers').doc(user.uid).get();
      final technicianDoc = await FirebaseFirestore.instance.collection('Technicians').doc(user.uid).get();
      final userDoc = await FirebaseFirestore.instance.collection('Users').doc(user.uid).get();
      
      String newRole = 'User';
      String newOrg = '-';
      
      if (adminDoc.exists) {
        newRole = 'Admin';
        final adminData = adminDoc.data();
        newOrg = adminData?['organization'] ?? '-';
      } 
      else if (developerDoc.exists) {
        newRole = 'Technician';
        newOrg = 'JV Almacis';
      }
      else if (technicianDoc.exists) {
        newRole = 'Technician';
        final techData = technicianDoc.data();
        newOrg = techData?['organization'] ?? '-';
      }
      else if (userDoc.exists) {
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
      }
    } catch (e) {
      _logger.e('Error getting user role: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: 'Settings',
      facilityId: widget.facilityId,
      currentRole: _currentRole,
      organization: _organization,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    final user = FirebaseAuth.instance.currentUser;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // User Profile Section
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'User Profile',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[800],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blueGrey[100],
                      child: Icon(Icons.person, color: Colors.blueGrey[700]),
                    ),
                    title: Text(
                      user?.email ?? 'User',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Tap to manage your profile',
                      style: GoogleFonts.poppins(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ProfileScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Notification Settings
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Notifications',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey[800],
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  if (_isLoadingNotifications)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    SwitchListTile(
                      title: Text('Enable Notifications', style: GoogleFonts.poppins()),
                      subtitle: Text(
                        _notificationsEnabled 
                            ? 'Receive maintenance reminders' 
                            : 'Notifications are disabled',
                        style: GoogleFonts.poppins(fontSize: 12),
                      ),
                      value: _notificationsEnabled,
                      onChanged: _updateNotificationSettings,
                      activeColor: Colors.blueGrey,
                    ),
                    
                    SwitchListTile(
                      title: Text('Email Notifications', style: GoogleFonts.poppins()),
                      subtitle: Text('Receive notifications via email', style: GoogleFonts.poppins(fontSize: 12)),
                      value: _emailNotifications,
                      onChanged: _notificationsEnabled ? (value) {
                        setState(() {
                          _emailNotifications = value;
                        });
                      } : null,
                    ),
                    
                    SwitchListTile(
                      title: Text('Push Notifications', style: GoogleFonts.poppins()),
                      subtitle: Text('Receive push notifications on device', style: GoogleFonts.poppins(fontSize: 12)),
                      value: _pushNotifications,
                      onChanged: _notificationsEnabled ? (value) {
                        setState(() {
                          _pushNotifications = value;
                        });
                      } : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // App Preferences
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'App Preferences',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[800],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  ListTile(
                    leading: Icon(Icons.palette, color: Colors.blueGrey[700]),
                    title: Text('Theme', style: GoogleFonts.poppins()),
                    subtitle: Text(_selectedTheme, style: GoogleFonts.poppins(fontSize: 12)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _showThemeDialog(),
                  ),
                  
                  ListTile(
                    leading: Icon(Icons.language, color: Colors.blueGrey[700]),
                    title: Text('Language', style: GoogleFonts.poppins()),
                    subtitle: Text(_selectedLanguage, style: GoogleFonts.poppins(fontSize: 12)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _showLanguageDialog(),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Support & Information
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Support & Information',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[800],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  ListTile(
                    leading: Icon(Icons.help, color: Colors.blueGrey[700]),
                    title: Text('Help & Support', style: GoogleFonts.poppins()),
                    subtitle: Text('Get help and contact support', style: GoogleFonts.poppins(fontSize: 12)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const HelpSupportScreen()),
                    ),
                  ),
                  
                  ListTile(
                    leading: Icon(Icons.info, color: Colors.blueGrey[700]),
                    title: Text('About', style: GoogleFonts.poppins()),
                    subtitle: Text('App information and version', style: GoogleFonts.poppins(fontSize: 12)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AboutScreen()),
                    ),
                  ),
                  
                  ListTile(
                    leading: Icon(Icons.privacy_tip, color: Colors.blueGrey[700]),
                    title: Text('Privacy Policy', style: GoogleFonts.poppins()),
                    subtitle: Text('View privacy policy', style: GoogleFonts.poppins(fontSize: 12)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _showPrivacyPolicy(),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Account Actions
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Account',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[800],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  ListTile(
                    leading: Icon(Icons.logout, color: Colors.red[700]),
                    title: Text('Sign Out', style: GoogleFonts.poppins(color: Colors.red[700])),
                    subtitle: Text('Sign out of your account', style: GoogleFonts.poppins(fontSize: 12)),
                    onTap: () => _showSignOutDialog(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select Theme', style: GoogleFonts.poppins()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['System', 'Light', 'Dark'].map((theme) {
            return RadioListTile<String>(
              title: Text(theme, style: GoogleFonts.poppins()),
              value: theme,
              groupValue: _selectedTheme,
              onChanged: (value) {
                setState(() {
                  _selectedTheme = value!;
                });
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select Language', style: GoogleFonts.poppins()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['English', 'Swahili'].map((language) {
            return RadioListTile<String>(
              title: Text(language, style: GoogleFonts.poppins()),
              value: language,
              groupValue: _selectedLanguage,
              onChanged: (value) {
                setState(() {
                  _selectedLanguage = value!;
                });
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Privacy Policy', style: GoogleFonts.poppins()),
        content: SingleChildScrollView(
          child: Text(
            'This CMMS application collects and processes data necessary for maintenance management operations. Your data is securely stored and processed in accordance with applicable data protection regulations.',
            style: GoogleFonts.poppins(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sign Out', style: GoogleFonts.poppins()),
        content: Text(
          'Are you sure you want to sign out?',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _performSignOut();
            },
            child: Text('Sign Out', style: GoogleFonts.poppins(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _performSignOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/login',
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error signing out: $e', style: GoogleFonts.poppins()),
          ),
        );
      }
    }
  }
}