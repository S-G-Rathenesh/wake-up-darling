import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CoupleService {
  CoupleService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static const String _users = 'users';
  static const String _pairingRequests = 'pairing_requests';
  static const String _couples = 'couples';

  Future<void> _cancelOtherPendingRequests({
    required List<String> memberUids,
    required String exceptRequestId,
  }) async {
    // Keep transactions clean: do cleanup in a separate batch.
    // This is best-effort; if it fails, pairing still succeeds.
    try {
      final pendingFrom = await _db
          .collection(_pairingRequests)
          .where('status', isEqualTo: 'pending')
          .where('fromUid', whereIn: memberUids)
          .get();

      final pendingTo = await _db
          .collection(_pairingRequests)
          .where('status', isEqualTo: 'pending')
          .where('toUid', whereIn: memberUids)
          .get();

      final batch = _db.batch();
      final seen = <String>{};

      for (final doc in [...pendingFrom.docs, ...pendingTo.docs]) {
        if (doc.id == exceptRequestId) continue;
        if (!seen.add(doc.id)) continue;

        batch.update(doc.reference, {
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    } catch (_) {
      // Ignore cleanup failures.
    }
  }

  Future<void> sendPairingRequest({required String partnerEmail}) async {
    final me = _auth.currentUser;
    if (me == null) throw Exception('Not logged in');

    await syncMyCoupleFromAcceptedRequests();

    final email = (me.email ?? '').trim();
    if (email.isEmpty) throw Exception('Missing your email');

    final targetEmail = partnerEmail.trim().toLowerCase();
    if (targetEmail.isEmpty) throw Exception('Enter partner email');
    if (targetEmail == email.toLowerCase()) {
      throw Exception("You can't pair with yourself");
    }

    final mySnap = await _db.collection(_users).doc(me.uid).get();
    final myData = mySnap.data() ?? <String, dynamic>{};
    if (myData['partnerId'] != null) {
      throw Exception('You are already connected to a partner');
    }

    final myPending = await _db
        .collection(_pairingRequests)
        .where('fromUid', isEqualTo: me.uid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (myPending.docs.isNotEmpty) {
      throw Exception('You already have a pending pairing request');
    }

    final userQuery = await _db
        .collection(_users)
        .where('email', isEqualTo: targetEmail)
        .limit(1)
        .get();

    if (userQuery.docs.isEmpty) {
      throw Exception('No user found with that email');
    }

    final partnerDoc = userQuery.docs.first;
    final partnerUid = partnerDoc.id;
    final partnerData = partnerDoc.data();

    if ((partnerData['partnerId'] ?? '')
        .toString()
        .trim()
        .isNotEmpty) {
      throw Exception('That user is already connected');
    }

    // If there is already an outgoing request to that partner, don't duplicate it.
    final existingToPartner = await _db
        .collection(_pairingRequests)
        .where('fromUid', isEqualTo: me.uid)
        .where('toUid', isEqualTo: partnerUid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (existingToPartner.docs.isNotEmpty) {
      throw Exception('Pairing request already sent');
    }

    await _db.collection(_pairingRequests).add({
      'fromUid': me.uid,
      'fromEmail': email.toLowerCase(),
      'toUid': partnerUid,
      'toEmail': targetEmail,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> incomingPairingRequests() {
    final me = _auth.currentUser;
    if (me == null) return const Stream.empty();

    return _db
        .collection(_pairingRequests)
        .where('toUid', isEqualTo: me.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  Future<void> syncMyCoupleFromAcceptedRequests() async {
    final me = _auth.currentUser;
    if (me == null) return;

    final mySnap = await _db.collection(_users).doc(me.uid).get();
    final myData = mySnap.data() ?? <String, dynamic>{};
    if ((myData['partnerId'] ?? '').toString().trim().isNotEmpty) return;

    final accepted = await _db
        .collection(_pairingRequests)
        .where('fromUid', isEqualTo: me.uid)
        .where('status', isEqualTo: 'accepted')
        .limit(1)
        .get();
    if (accepted.docs.isEmpty) return;

    final req = accepted.docs.first.data();
    final partnerUid = (req['toUid'] ?? '').toString();
    final partnerEmail = (req['toEmail'] ?? '').toString().trim().toLowerCase();
    final coupleId = (req['coupleId'] ?? '').toString();

    if (partnerUid.isEmpty || coupleId.isEmpty) return;

    await _db.collection(_users).doc(me.uid).set(
      {
        'partnerId': partnerUid,
        'partnerEmail': partnerEmail,
        'coupleId': coupleId,
      },
      SetOptions(merge: true),
    );
  }

  Future<void> acceptPairingRequest({
    required String requestId,
    required String partnerUid,
    required String partnerEmail,
  }) async {
    final me = _auth.currentUser;
    if (me == null) throw Exception('Not logged in');

    await _db.runTransaction((txn) async {
      final myRef = _db.collection(_users).doc(me.uid);
      final partnerRef = _db.collection(_users).doc(partnerUid);
      final requestRef = _db.collection(_pairingRequests).doc(requestId);
      final coupleRef = _db.collection(_couples).doc();

      final mySnap = await txn.get(myRef);
      final partnerSnap = await txn.get(partnerRef);
      final requestSnap = await txn.get(requestRef);

      final myData = mySnap.data() ?? <String, dynamic>{};
      final partnerData = partnerSnap.data() ?? <String, dynamic>{};
      final requestData = requestSnap.data() ?? <String, dynamic>{};

      if (myData['partnerId'] != null) {
        throw Exception('You are already connected');
      }
      if (partnerData['partnerId'] != null) {
        throw Exception('Partner is already connected');
      }
      if (requestData['status'] != 'pending') {
        throw Exception('Request is no longer pending');
      }
      if (requestData['toUid'] != me.uid) {
        throw Exception('Invalid pairing request');
      }
      if (requestData['fromUid'] != partnerUid) {
        throw Exception('Invalid pairing request');
      }

      txn.set(coupleRef, {
        'memberUids': [me.uid, partnerUid],
        'createdAt': FieldValue.serverTimestamp(),
      });

      txn.update(requestRef, {
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'coupleId': coupleRef.id,
      });

      final resolvedPartnerEmail = (requestData['fromEmail'] ?? partnerEmail)
          .toString()
          .trim()
          .toLowerCase();

      txn.update(myRef, {
        'partnerId': partnerUid,
        'partnerEmail': resolvedPartnerEmail,
        'coupleId': coupleRef.id,
      });

    });

    await _cancelOtherPendingRequests(
      memberUids: [me.uid, partnerUid],
      exceptRequestId: requestId,
    );
  }

  Future<void> declinePairingRequest({required String requestId}) async {
    final me = _auth.currentUser;
    if (me == null) throw Exception('Not logged in');

    await _db.collection(_pairingRequests).doc(requestId).update({
      'status': 'declined',
      'declinedAt': FieldValue.serverTimestamp(),
    });
  }
}
