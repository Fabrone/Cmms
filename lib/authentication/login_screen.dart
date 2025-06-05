import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/authentication/registration_screen.dart';
import 'package:cmms/screens/dashboard_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logger/logger.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final Logger _logger = Logger();
  bool _isLoading = false;
  String? _errorMessage;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    try {
      // Configure Firebase Auth persistence for web
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
        _logger.i('Set Firebase Auth persistence to LOCAL for web');
      }
      
      // Check if user is already logged in
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _logger.i('User already logged in: ${user.uid}');
        await _fetchUserRole();
        if (mounted) {
          _navigateToDashboard();
        }
      }
    } catch (e) {
      _logger.e('Error initializing auth: $e');
    }
  }

  Future<void> _fetchUserRole() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Check collections in order of priority
      DocumentSnapshot adminDoc = await FirebaseFirestore.instance
          .collection('Admins')
          .doc(user.uid)
          .get();
      if (adminDoc.exists) {
        setState(() => _userRole = 'Admin');
        return;
      }

      DocumentSnapshot developerDoc = await FirebaseFirestore.instance
          .collection('Developers')
          .doc(user.uid)
          .get();
      if (developerDoc.exists) {
        setState(() => _userRole = 'Technician'); // Developers are treated as Technicians
        return;
      }

      DocumentSnapshot technicianDoc = await FirebaseFirestore.instance
          .collection('Technicians')
          .doc(user.uid)
          .get();
      if (technicianDoc.exists) {
        setState(() => _userRole = 'Technician');
        return;
      }

      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .get();
      // Fix: Cast the data to Map<String, dynamic> to access fields
      if (userDoc.exists && (userDoc.data() as Map<String, dynamic>?)?['role'] == 'Technician') {
        setState(() => _userRole = 'Technician');
        return;
      }

      setState(() => _userRole = 'User');
    } catch (e) {
      _logger.e('Error fetching role: $e');
      setState(() => _errorMessage = 'Error fetching role: $e');
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Configure persistence before login
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      }

      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      _logger.i('User logged in successfully: ${userCredential.user?.uid}');

      // Fetch user role after successful login
      await _fetchUserRole();

      if (mounted) {
        _navigateToDashboard();
      }
    } on FirebaseAuthException catch (e) {
      _logger.e('Firebase Auth error: ${e.code} - ${e.message}');
      setState(() {
        switch (e.code) {
          case 'user-not-found':
            _errorMessage = 'No user found with this email address.';
            break;
          case 'wrong-password':
            _errorMessage = 'Incorrect password.';
            break;
          case 'invalid-email':
            _errorMessage = 'Invalid email address.';
            break;
          case 'user-disabled':
            _errorMessage = 'This user account has been disabled.';
            break;
          case 'too-many-requests':
            _errorMessage = 'Too many failed login attempts. Please try again later.';
            break;
          default:
            _errorMessage = 'Login failed: ${e.message}';
        }
      });
    } catch (e) {
      _logger.e('General login error: $e');
      setState(() {
        _errorMessage = 'An unexpected error occurred. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToDashboard() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => DashboardScreen(
          facilityId: '', // Empty facility ID to trigger facility selection
          role: _userRole ?? 'User',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth > 800 ? screenWidth * 0.6 : screenWidth * 0.9;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Login', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueGrey,
        automaticallyImplyLeading: false, // Remove back button to prevent logout
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              constraints: BoxConstraints(maxWidth: contentWidth),
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Welcome Back',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 20),
                    if (_userRole != null)
                      Text(
                        'You have been assigned the ${_userRole == 'Admin' ? 'Admin' : _userRole == 'Technician' ? 'Technician' : _userRole} role.',
                        style: const TextStyle(fontSize: 16, color: Colors.blueGrey, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Please enter your email';
                        if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) return 'Enter a valid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Please enter your password';
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red[200]!),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red[700]),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 20),
                    _isLoading
                        ? const CircularProgressIndicator()
                        : ElevatedButton(
                            onPressed: _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueGrey,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              minimumSize: const Size(double.infinity, 50),
                            ),
                            child: const Text('Login', style: TextStyle(fontSize: 16)),
                          ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const RegistrationScreen()),
                        );
                      },
                      child: const Text('Need an account? Sign Up', style: TextStyle(color: Colors.blueGrey)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}