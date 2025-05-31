import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/authentication/login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final String facilityId;

  const SettingsScreen({super.key, required this.facilityId});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();

  Future<void> _handleLogout() async {
    try {
      final bool? confirmLogout = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Confirm Logout', style: GoogleFonts.poppins()),
          content: Text(
            'Are you sure you want to log out?',
            style: GoogleFonts.poppins(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Text('Logout', style: GoogleFonts.poppins()),
            ),
          ],
        ),
      );

      if (confirmLogout == true) {
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      _logger.e('Error logging out: $e');
      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error logging out: $e', style: GoogleFonts.poppins())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: ScaffoldMessenger(
        key: _messengerKey,
        child: Scaffold(
          extendBodyBehindAppBar: false,
          appBar: AppBar(
            title: Text(
              'Settings',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            backgroundColor: Colors.blueGrey,
            iconTheme: const IconThemeData(color: Colors.white),
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            elevation: 0,
          ),
          body: SingleChildScrollView(  // Changed from Padding to SingleChildScrollView for scrollability
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Application Settings',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey[800],
                  ),
                ),
                const SizedBox(height: 24),
                
                // Account Section
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Account',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        ListTile(
                          leading: const Icon(Icons.person, color: Colors.blueGrey),
                          title: Text('Profile', style: GoogleFonts.poppins()),
                          subtitle: Text('View and edit your profile', style: GoogleFonts.poppins(fontSize: 12)),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () {
                            _messengerKey.currentState?.showSnackBar(
                              SnackBar(content: Text('Profile feature coming soon', style: GoogleFonts.poppins())),
                            );
                          },
                        ),
                        
                        const Divider(),
                        
                        ListTile(
                          leading: const Icon(Icons.notifications, color: Colors.blueGrey),
                          title: Text('Notifications', style: GoogleFonts.poppins()),
                          subtitle: Text('Manage notification preferences', style: GoogleFonts.poppins(fontSize: 12)),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () {
                            _messengerKey.currentState?.showSnackBar(
                              SnackBar(content: Text('Notification settings coming soon', style: GoogleFonts.poppins())),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // App Section
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Application',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        ListTile(
                          leading: const Icon(Icons.info, color: Colors.blueGrey),
                          title: Text('About', style: GoogleFonts.poppins()),
                          subtitle: Text('App version and information', style: GoogleFonts.poppins(fontSize: 12)),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text('About CMMS', style: GoogleFonts.poppins()),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Version: 1.0.0', style: GoogleFonts.poppins()),
                                    const SizedBox(height: 8),
                                    Text('Computerized Maintenance Management System', style: GoogleFonts.poppins()),
                                    const SizedBox(height: 8),
                                    Text('© 2025 Swedish Embassy', style: GoogleFonts.poppins()),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: Text('OK', style: GoogleFonts.poppins()),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        
                        const Divider(),
                        
                        ListTile(
                          leading: const Icon(Icons.help, color: Colors.blueGrey),
                          title: Text('Help & Support', style: GoogleFonts.poppins()),
                          subtitle: Text('Get help and contact support', style: GoogleFonts.poppins(fontSize: 12)),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () {
                            _messengerKey.currentState?.showSnackBar(
                              SnackBar(content: Text('Help & Support coming soon', style: GoogleFonts.poppins())),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),  // Changed from Spacer() to fixed height
                
                // Logout Section
                Card(
                  elevation: 2,
                  color: Colors.red[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Account Actions',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.red[800],
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        ListTile(
                          leading: const Icon(Icons.logout, color: Colors.red),
                          title: Text('Logout', style: GoogleFonts.poppins(color: Colors.red[700])),
                          subtitle: Text('Sign out of your account', style: GoogleFonts.poppins(fontSize: 12, color: Colors.red[600])),
                          onTap: _handleLogout,
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}