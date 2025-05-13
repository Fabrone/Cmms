import 'package:cmms/authentication/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
//import 'package:cmms/authentication/registration_screen.dart';

class HomeScreen extends StatelessWidget {
  final String facilityId;

  const HomeScreen({super.key, required this.facilityId});

  Future<void> _handleLogout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth > 800 ? screenWidth * 0.6 : screenWidth * 0.9;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CMMS Welcome'),
        backgroundColor: Colors.blueGrey,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _handleLogout(context),
            tooltip: 'Log Out',
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              constraints: BoxConstraints(maxWidth: contentWidth),
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Welcome to CMMS!',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'CMMS (Computerized Maintenance Management System) helps you manage facility maintenance, track work orders, and ensure operational efficiency. Register and wait for Admin approval to access features tailored to your role, such as work orders, inventory management, preventive maintenance, and more.',
                    style: TextStyle(fontSize: 16, color: Colors.blueGrey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'Your registration is complete. Please wait for admin to approve your login.',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.blueGrey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  // Placeholder Request Login Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: null, 
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[400],
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text(
                        '(Pending Admin Approval)',
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}