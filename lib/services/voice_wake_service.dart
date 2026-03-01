import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/voice_wake_request_model.dart';
import 'local_media_service.dart';

/// Handles recording, uploading, and creating voice wake requests.
///
/// Firestore layout:
///   VoiceWakeRequests/{requestId}
///
/// Media storage: Local private app storage
class VoiceWakeService {
  VoiceWakeService({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get _myUid => _auth.currentUser?.uid ?? '';

  /// Upload the recorded voice file and create a VoiceWakeRequest document.
  /// Returns the document ID.
  Future<String> createVoiceWakeRequest({
    required String coupleId,
    required String receiverId,
    required File audioFile,
    required DateTime scheduledTime,
    int durationMs = 0,
  }) async {
    // ── Step 1: Validate file exists ──────────────────────────────────────
    if (!audioFile.existsSync()) {
      debugPrint('[VoiceWakeService] ERROR: Audio file not found: ${audioFile.path}');
      throw Exception('Audio file not found at ${audioFile.path}');
    }
    final fileSize = audioFile.lengthSync();
    if (fileSize == 0) {
      debugPrint('[VoiceWakeService] ERROR: Audio file is empty (0 bytes)');
      throw Exception('Audio file is empty');
    }
    debugPrint('[VoiceWakeService] File exists: ${audioFile.path} ($fileSize bytes)');

    // ── Step 2: Save to local private storage ──────────────────────────────
    final fileName = 'vw_${DateTime.now().millisecondsSinceEpoch}.m4a';
    debugPrint('[VoiceWakeService] Saving voice wake locally → $fileName');
    final localPath = await LocalMediaService.saveFileToPrivate(audioFile, fileName);
    debugPrint('[VoiceWakeService] Saved locally – path: $localPath');
    final url = localPath; // stored as local path

    // 2. Write Firestore document.
    final request = VoiceWakeRequest(
      id: '',
      senderId: _myUid,
      receiverId: receiverId,
      coupleId: coupleId,
      voiceUrl: url,
      durationMs: durationMs,
      scheduledTime: scheduledTime,
      status: 'pending',
      createdAt: DateTime.now(),
    );

    // ── Step 4: Save to Firestore ──────────────────────────────────────────
    final docRef =
        await _db.collection('VoiceWakeRequests').add(request.toMap());
    debugPrint('[VoiceWakeService] Firestore VoiceWakeRequests doc saved: ${docRef.id}');

    // 5. Also write to the couple doc so the Cloud Function can send FCM.
    await _db.collection('couples').doc(coupleId).update({
      'voiceWake': {
        'requestId': docRef.id,
        'senderId': _myUid,
        'receiverId': receiverId,
        'voiceUrl': url,
        'scheduledTimeMs': scheduledTime.millisecondsSinceEpoch,
        'status': 'pending',
        'timestamp': Timestamp.now(),
      },
    });
    debugPrint('[VoiceWakeService] Couple doc updated with voiceWake field');

    debugPrint('[VoiceWakeService] ✅ Voice wake request complete: ${docRef.id}');
    return docRef.id;
  }

  /// Stream of incoming voice wake requests for the current user.
  Stream<List<VoiceWakeRequest>> incomingRequests() {
    return _db
        .collection('VoiceWakeRequests')
        .where('receiverId', isEqualTo: _myUid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => VoiceWakeRequest.fromDoc(d)).toList());
  }

  /// Update the status of a voice wake request.
  Future<void> updateStatus(String requestId, String status) async {
    await _db.collection('VoiceWakeRequests').doc(requestId).update({
      'status': status,
    });
  }

  /// Returns true if current time is within college hours (08:00–17:30).
  static bool isCollegeTime() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 8, 0);
    final end = DateTime(now.year, now.month, now.day, 17, 30);
    return now.isAfter(start) && now.isBefore(end);
  }
}
