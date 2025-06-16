import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/authentication/registration_screen.dart';
import 'package:cmms/screens/dashboard_screen.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  SplashScreenState createState() => SplashScreenState();
}

class SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _damageOpacityAnimation;
  late Animation<double> _repairScaleAnimation;
  late Animation<double> _textFadeAnimation;
  final Logger _logger = Logger(printer: PrettyPrinter());
  String? _currentRole;
  bool _navigationCompleted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );

    _damageOpacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
      ),
    );

    _repairScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 0.8, curve: Curves.easeOutBack),
      ),
    );

    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.6, 0.9, curve: Curves.easeIn),
      ),
    );

    _controller.forward();

    SchedulerBinding.instance.addPostFrameCallback((_) {
      _initializeAuthAndRoleCheck();
    });
  }

  Future<void> _initializeAuthAndRoleCheck() async {
    try {
      // Configure Firebase Auth persistence for web
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      }

      // Wait for auth state to be ready
      await Future.delayed(const Duration(seconds: 2));
      
      User? user = FirebaseAuth.instance.currentUser;
      _logger.i('Current user: ${user?.uid ?? 'null'}');
      
      if (user == null) {
        _navigateToRegistration('No user logged in');
        return;
      }

      // Check if user exists in Users collection
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        _navigateToRegistration('User not registered');
        return;
      }

      // Initialize role listeners
      await _determineUserRole(user.uid);

      // Wait for animation to complete before navigation
      await Future.delayed(const Duration(seconds: 3));
      
      if (!_navigationCompleted) {
        _navigateBasedOnRole();
      }
    } catch (e) {
      _logger.e('Error in auth initialization: $e');
      if (!_navigationCompleted) {
        _navigateToRegistration('Authentication error: $e');
      }
    }
  }

  Future<void> _determineUserRole(String uid) async {
    try {
      // Check collections in order of priority
      final adminDoc = await FirebaseFirestore.instance
          .collection('Admins')
          .doc(uid)
          .get();
      
      final developerDoc = await FirebaseFirestore.instance
          .collection('Developers')
          .doc(uid)
          .get();
      
      final technicianDoc = await FirebaseFirestore.instance
          .collection('Technicians')
          .doc(uid)
          .get();
      
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(uid)
          .get();

      if (mounted) {
        setState(() {
          if (adminDoc.exists) {
            _currentRole = 'Admin';
            _logger.i('User is an Admin');
          } else if (developerDoc.exists) {
            _currentRole = 'Technician'; // Developers are treated as Technicians
            _logger.i('User is a Developer (treated as Technician)');
          } else if (technicianDoc.exists) {
            _currentRole = 'Technician';
            _logger.i('User is a Technician');
          } else if (userDoc.exists && userDoc.data()?['role'] == 'Technician') {
            _currentRole = 'Technician';
            _logger.i('User has Technician role in Users collection');
          } else {
            _currentRole = 'User';
            _logger.i('User has default User role');
          }
        });
      }

      // Set up real-time listeners for role changes
      _listenToRoleChanges(uid);
    } catch (e) {
      _logger.e('Error determining user role: $e');
      _currentRole = 'User';
    }
  }

  void _listenToRoleChanges(String uid) {
    const roleCollections = ['Admins', 'Developers', 'Technicians'];

    for (String collection in roleCollections) {
      FirebaseFirestore.instance
          .collection(collection)
          .doc(uid)
          .snapshots()
          .listen((snapshot) async {
        if (mounted && !_navigationCompleted) {
          setState(() {
            if (snapshot.exists) {
              _currentRole = collection == 'Admins'
                  ? 'Admin'
                  : collection == 'Developers'
                      ? 'Technician'
                      : 'Technician';
            } else if (_currentRole == (collection == 'Admins'
                    ? 'Admin'
                    : collection == 'Developers'
                        ? 'Technician'
                        : 'Technician')) {
              _currentRole = 'User';
            }
          });
        }
      }, onError: (e) {
        _logger.e('Error listening to $collection role: $e');
      });
    }

    // Listen to auth state changes
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null && mounted && !_navigationCompleted) {
        _navigateToRegistration('User logged out');
      }
    });
  }

  void _navigateBasedOnRole() {
    if (!mounted || _navigationCompleted) return;

    _navigationCompleted = true;
    _logger.i('Navigating to dashboard with role: ${_currentRole ?? 'User'}');

    // Always navigate to DashboardScreen - let it handle facility selection
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => DashboardScreen(
          facilityId: '', // Empty facility ID to trigger facility selection
          role: _currentRole ?? 'User',
        ),
      ),
    );
  }

  void _navigateToRegistration(String message) {
    if (mounted && !_navigationCompleted) {
      _navigationCompleted = true;
      _logger.i('Navigating to registration: $message');
      
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const RegistrationScreen()),
      );
      
      // Show message after navigation
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Colors.blueGrey[50],
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: _damageOpacityAnimation.value,
                        child: const Icon(
                          Icons.broken_image,
                          size: 150,
                          color: Colors.redAccent,
                        ),
                      ),
                      Transform.scale(
                        scale: _repairScaleAnimation.value,
                        child: const Icon(
                          Icons.business,
                          size: 150,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Opacity(
                    opacity: _textFadeAnimation.value,
                    child: const Column(
                      children: [
                        Text(
                          'NyumbaSmart',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey,
                          ),
                        ),
                        Text(
                          'Build, Maintain, Succeed',
                          style: TextStyle(
                            fontSize: 20,
                            fontStyle: FontStyle.italic,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}