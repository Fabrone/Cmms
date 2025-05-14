import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/authentication/registration_screen.dart';
import 'package:cmms/screens/dashboard_screen.dart';
import 'package:logger/logger.dart';

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
    User? user = FirebaseAuth.instance.currentUser;
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
    _listenToRoleChanges(user.uid);

    // Delay navigation slightly to allow initial role check
    await Future.delayed(const Duration(seconds: 5));
    _navigateBasedOnRole();
  }

  void _listenToRoleChanges(String uid) {
    const roleCollections = ['Admins', 'Developers', 'Technicians'];

    for (String collection in roleCollections) {
      FirebaseFirestore.instance
          .collection(collection)
          .doc(uid)
          .snapshots()
          .listen((snapshot) {
        if (mounted) {
          setState(() {
            if (snapshot.exists) {
              _currentRole = collection == 'Admins'
                  ? 'MainAdmin'
                  : collection == 'Developers'
                      ? 'Developer'
                      : 'Technician';
            } else if (_currentRole == (collection == 'Admins'
                    ? 'MainAdmin'
                    : collection == 'Developers'
                        ? 'Developer'
                        : 'Technician')) {
              _currentRole = 'User';
            }
          });
          _navigateBasedOnRole();
        }
      }, onError: (e) {
        _logger.e('Error listening to $collection role: $e');
      });
    }

    // Listen to auth state
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null && mounted) {
        _navigateToRegistration('User logged out');
      }
    });
  }

  void _navigateBasedOnRole() {
    if (!mounted) return;

    // Navigate to DashboardScreen with the current role
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => DashboardScreen(
          facilityId: 'facility1',
          role: _currentRole ?? 'User',
        ),
      ),
    );
  }

  void _navigateToRegistration(String message) {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const RegistrationScreen()),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
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
                          'CMMS',
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