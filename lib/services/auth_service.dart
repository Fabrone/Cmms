import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Logger _logger = Logger();

  Stream<User?> get user => _auth.authStateChanges();

  Future<User?> signIn(String email, String password) async {
    try {
      _logger.i('Attempting to sign in with email: $email');
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      _logger.i('Sign-in successful for user: ${result.user?.uid}');
      return result.user;
    } catch (e, stackTrace) {
      _logger.e('Sign-in error: $e', stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<User?> signUp(String email, String password) async {
    try {
      _logger.i('Attempting to sign up with email: $email');
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? user = result.user;
      if (user != null) {
        // Create user document in Firestore
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'email': email,
          'role': 'client', // Default role
          'createdAt': Timestamp.now(),
        });
        _logger.i('User document created for UID: ${user.uid}');
      }
      _logger.i('Sign-up successful for user: ${user?.uid}');
      return user;
    } catch (e, stackTrace) {
      _logger.e('Sign-up error: $e', stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      _logger.i('Attempting to sign out');
      await _auth.signOut();
      _logger.i('Sign-out successful');
    } catch (e, stackTrace) {
      _logger.e('Sign-out error: $e', stackTrace: stackTrace);
      rethrow;
    }
  }
}