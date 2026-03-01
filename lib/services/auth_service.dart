import 'package:firebase_auth/firebase_auth.dart';

import 'user_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserService _userService = UserService();

  Future<User> register(String email, String password) async {
    try {
      if (email.trim().isEmpty || password.isEmpty) {
        throw Exception('Email and password are required');
      }
      final result = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = result.user;
      if (user == null) {
        throw Exception('Registration failed');
      }

      // Ensure Firestore profile exists for new accounts.
      await _userService.ensureUserProfileExists(user: user);
      return user;
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendlyAuthMessage(e));
    }
  }

  Future<User> login(String email, String password) async {
    try {
      if (email.trim().isEmpty || password.isEmpty) {
        throw Exception('Email and password are required');
      }
      final result = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = result.user;
      if (user == null) {
        throw Exception('Login failed');
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendlyAuthMessage(e));
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
  }

  User? get currentUser => _auth.currentUser;

  String _friendlyAuthMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Invalid email address';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'user-not-found':
        return 'No account found for that email';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password';
      case 'email-already-in-use':
        return 'An account already exists for that email';
      case 'weak-password':
        return 'Password is too weak';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled in Firebase';
      case 'network-request-failed':
        return 'Network error. Please check your connection';
      default:
        return e.message ?? 'Authentication failed';
    }
  }
}
