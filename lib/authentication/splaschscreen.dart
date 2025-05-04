import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/authentication/registration_screen.dart';
import 'package:cmms/authentication/homescreen.dart';
import 'package:cmms/authentication/login_screen.dart';

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
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          _navigateBasedOnAuthState();
        }
      });
    });
  }

  Future<void> _navigateBasedOnAuthState() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Unauthenticated, navigate to RegistrationScreen
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const RegistrationScreen()),
        );
      }
      return;
    }

    try {
      // Check if user exists in Users collection
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        // Not in Users, navigate to RegistrationScreen
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const RegistrationScreen()),
          );
        }
        return;
      }

      // Check for roles
      DocumentSnapshot developerDoc = await FirebaseFirestore.instance
          .collection('Developers')
          .doc(user.uid)
          .get();

      if (developerDoc.exists) {
        // Developer, navigate to LoginScreen
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
        return;
      }

      DocumentSnapshot adminDoc = await FirebaseFirestore.instance
          .collection('Admins')
          .doc(user.uid)
          .get();

      if (adminDoc.exists) {
        // MainAdmin, navigate to LoginScreen
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
        return;
      }

      DocumentSnapshot seniorFMManagerDoc = await FirebaseFirestore.instance
          .collection('SeniorFMManagers')
          .doc(user.uid)
          .get();

      if (seniorFMManagerDoc.exists) {
        // SeniorFMManager, navigate to LoginScreen
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
        return;
      }

      DocumentSnapshot technicianDoc = await FirebaseFirestore.instance
          .collection('Technicians')
          .doc(user.uid)
          .get();

      if (technicianDoc.exists) {
        // Technician, navigate to LoginScreen
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
        return;
      }

      DocumentSnapshot requesterDoc = await FirebaseFirestore.instance
          .collection('Requesters')
          .doc(user.uid)
          .get();

      if (requesterDoc.exists) {
        // Requester, navigate to LoginScreen
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
        return;
      }

      DocumentSnapshot auditorInspectorDoc = await FirebaseFirestore.instance
          .collection('AuditorsInspectors')
          .doc(user.uid)
          .get();

      if (auditorInspectorDoc.exists) {
        // Auditor/Inspector, navigate to LoginScreen
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
        return;
      }

      // No role assigned, navigate to HomeScreen
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen(facilityId: 'facility1')),
        );
      }
    } catch (e) {
      // Fallback to RegistrationScreen on error
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const RegistrationScreen()),
        );
      }
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