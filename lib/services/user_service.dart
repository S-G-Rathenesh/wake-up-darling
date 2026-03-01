import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_model.dart';

class UserService {
  UserService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static const String _usersCollection = 'users';

  DocumentReference<Map<String, dynamic>> _userRef(String uid) {
    return _db.collection(_usersCollection).doc(uid);
  }

  Future<void> ensureUserProfileExists({User? user}) async {
    final u = user ?? _auth.currentUser;
    if (u == null) return;

    final email = (u.email ?? '').trim();
    if (email.isEmpty) return;

    try {
      final ref = _userRef(u.uid);
      final snap = await ref.get();
      if (snap.exists) return;

      final defaultName = email.contains('@') ? email.split('@').first : email;
      final newUser = AppUser(
        uid: u.uid,
        email: email,
        name: defaultName,
        bio: '',
        partnerId: null,
        partnerEmail: null,
        coupleId: null,
        isOnline: true,
        lastSeen: DateTime.now(),
        streakCount: 0,
        blockedUsers: const [],
      );

      await ref.set(
        {
          ...newUser.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: false),
      );
    } on FirebaseException catch (e) {
      // This is often called from app/screen startup. Failing to create the
      // profile should not block UI or crash the app.
      // Auth-required writes can legitimately fail depending on rules.
      if (e.code == 'permission-denied') return;
      if (e.code == 'unavailable') return;
      return;
    } catch (_) {
      return;
    }
  }

  Future<void> createUserProfile({required User user, required String name}) async {
    final email = user.email;
    if (email == null || email.isEmpty) {
      throw Exception('Missing email on user');
    }

    final newUser = AppUser(
      uid: user.uid,
      email: email,
      name: name,
      bio: "",
      partnerId: null,
      partnerEmail: null,
      coupleId: null,
      isOnline: true,
      lastSeen: DateTime.now(),
      streakCount: 0,
      blockedUsers: const [],
    );

    try {
      await _userRef(user.uid).set(newUser.toMap(), SetOptions(merge: false));
    } on FirebaseException catch (e) {
      throw Exception(_friendlyFirestoreMessage(e));
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> getCurrentUserProfile() {
    final user = _auth.currentUser;
    if (user == null) {
      return const Stream.empty();
    }
    return _userRef(user.uid).snapshots();
  }

  Future<void> setOnlineStatus(bool status) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _userRef(user.uid).set(
        {
          'isOnline': status,
          'lastSeen': DateTime.now(),
          'uid': user.uid,
          'email': user.email,
        },
        SetOptions(merge: true),
      );
    } on FirebaseException catch (e) {
      // Presence updates should never crash the app.
      if (e.code == 'permission-denied') return;
      return;
    } catch (_) {
      return;
    }
  }

  Future<void> saveFCMToken(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _userRef(user.uid).set({'fcmToken': token}, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return;
      return;
    } catch (_) {
      return;
    }
  }

  Future<void> updateProfile(String name, String bio) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Not logged in');
    }
    try {
      await _userRef(user.uid).update({'name': name, 'bio': bio});
    } on FirebaseException catch (e) {
      throw Exception(_friendlyFirestoreMessage(e));
    }
  }

  Future<void> updateStreak(String partnerUid) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final today = DateTime.now().toString().substring(0, 10);

    await _db.collection("wake_history").add({
      'uid': user.uid,
      'partnerUid': partnerUid,
      'wakeDate': today,
      'completed': true,
    });

    await _userRef(user.uid).update({'streakCount': FieldValue.increment(1)});
  }

  Future<void> removePartner(String partnerUid) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _userRef(user.uid).update({'partnerId': null});
    await _userRef(partnerUid).update({'partnerId': null});
  }

  Future<void> blockUser(String uidToBlock) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _userRef(user.uid).update({
      'blockedUsers': FieldValue.arrayUnion([uidToBlock])
    });
  }

  String _friendlyFirestoreMessage(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'Permission denied. Please sign in and try again.';
      case 'unavailable':
        return 'Service unavailable. Please check your connection.';
      default:
        return e.message ?? 'Database error';
    }
  }
}
