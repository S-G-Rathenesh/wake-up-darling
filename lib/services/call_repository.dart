import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/call_model.dart';

/// Firestore-based call signaling repository.
///
/// Handles CRUD operations on the `Calls` collection for voice/video call
/// signaling. WebRTC media transport is NOT handled here — this class only
/// manages the signaling state machine:
///
///   calling → accepted → ended
///                ↘ rejected
///
/// Usage:
///   final repo = CallRepository();
///   final callId = await repo.startCall(...);
///   repo.listenCallStatus(callId, (status) { ... });
class CallRepository {
  CallRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _callsRef =>
      _db.collection('Calls');

  // ─── 1) Start a call ────────────────────────────────────────────────────

  /// Creates a new call document in Firestore and returns the generated
  /// [callId]. The status is set to `"calling"`.
  Future<String> startCall({
    required String callerId,
    required String callerName,
    required String receiverId,
    required String receiverName,
    required String coupleId,
    required String type, // 'voice' or 'video'
  }) async {
    final docRef = _callsRef.doc(); // auto-generated ID
    final callId = docRef.id;

    final call = CallModel(
      id: callId,
      callerId: callerId,
      callerName: callerName,
      receiverId: receiverId,
      receiverName: receiverName,
      coupleId: coupleId,
      type: type,
      status: 'calling',
      timestamp: DateTime.now(),
    );

    await docRef.set({
      ...call.toMap(),
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Write to couple doc so the receiver side can discover the call easily.
    try {
      await _db.collection('couples').doc(coupleId).update({
        'activeCall': {
          'callId': callId,
          'callerId': callerId,
          'callerName': callerName,
          'receiverId': receiverId,
          'type': type,
          'status': 'calling',
          'timestamp': FieldValue.serverTimestamp(),
        },
      });
    } catch (e) {
      debugPrint('[CallRepository] Failed to write activeCall to couple doc: $e');
    }

    return callId;
  }

  // ─── 2) Listen for incoming calls ───────────────────────────────────────

  /// Listens for incoming calls where [currentUserId] is the receiver and
  /// the status is `"calling"`. Returns the [StreamSubscription] so the
  /// caller can cancel it in lifecycle methods.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
      listenForIncomingCalls({
    required String currentUserId,
    required void Function(CallModel call) onIncomingCall,
  }) {
    return _callsRef
        .where('receiverId', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'calling')
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final call = CallModel.fromDoc(change.doc);
          onIncomingCall(call);
        }
      }
    });
  }

  // ─── 3) Update call status ──────────────────────────────────────────────

  /// Updates the `status` field of a call document.
  /// Valid statuses: `"calling" | "accepted" | "rejected" | "ended"`.
  Future<void> updateCallStatus(String callId, String status) async {
    try {
      await _callsRef.doc(callId).update({
        'status': status,
        if (status == 'ended' || status == 'rejected')
          'endedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[CallRepository] updateCallStatus error: $e');
    }
  }

  // ─── 4) Listen for call status changes ──────────────────────────────────

  /// Listens to real-time status changes on a single call document.
  /// Returns the [StreamSubscription] so the caller can cancel it.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> listenCallStatus({
    required String callId,
    required void Function(String status) onStatusChanged,
  }) {
    return _callsRef.doc(callId).snapshots().listen((snap) {
      if (!snap.exists) {
        onStatusChanged('ended');
        return;
      }
      final status = snap.data()?['status']?.toString() ?? 'ended';
      onStatusChanged(status);
    });
  }

  // ─── 5) Delete call document (cleanup) ──────────────────────────────────

  /// Deletes the call document and clears `activeCall` from the couple doc.
  Future<void> deleteCallDocument(String callId, String coupleId) async {
    try {
      await _callsRef.doc(callId).delete();
    } catch (_) {}

    try {
      await _db.collection('couples').doc(coupleId).update({
        'activeCall': FieldValue.delete(),
      });
    } catch (_) {}
  }

  // ─── 6) End and cleanup ─────────────────────────────────────────────────

  /// Convenience: sets status to `"ended"`, then deletes the document.
  Future<void> endAndCleanup(String callId, String coupleId) async {
    await updateCallStatus(callId, 'ended');
    await deleteCallDocument(callId, coupleId);
  }

  // ─── 7) Fetch single call ──────────────────────────────────────────────

  /// Fetches a single call document by ID. Returns `null` if not found.
  Future<CallModel?> getCall(String callId) async {
    final snap = await _callsRef.doc(callId).get();
    if (!snap.exists) return null;
    return CallModel.fromDoc(snap);
  }

  // ─── Placeholder: WebRTC integration ──────────────────────────────────

  /// Placeholder for future WebRTC peer connection setup.
  /// Call this after status becomes `"accepted"` on both sides.
  void startWebRTC(String callId) {
    // TODO: Initialize RTCPeerConnection
    // TODO: Exchange SDP offer/answer via Calls/{callId}
    // TODO: Exchange ICE candidates via Calls/{callId}/candidates
    // TODO: Attach local/remote media streams
  }
}
