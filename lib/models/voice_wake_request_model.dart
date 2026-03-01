import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a voice‐message wake request stored in
/// `WakeRequests/{requestId}`.
class VoiceWakeRequest {
  final String id;
  final String senderId;
  final String receiverId;
  final String coupleId;
  final String voiceUrl;         // Firebase Storage download URL
  final int durationMs;
  final DateTime scheduledTime;
  final String status;           // pending | delivered | played | cancelled
  final DateTime createdAt;

  VoiceWakeRequest({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.coupleId,
    required this.voiceUrl,
    this.durationMs = 0,
    required this.scheduledTime,
    this.status = 'pending',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'coupleId': coupleId,
      'voiceUrl': voiceUrl,
      'durationMs': durationMs,
      'scheduledTime': Timestamp.fromDate(scheduledTime),
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory VoiceWakeRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return VoiceWakeRequest(
      id: doc.id,
      senderId: d['senderId'] ?? '',
      receiverId: d['receiverId'] ?? '',
      coupleId: d['coupleId'] ?? '',
      voiceUrl: d['voiceUrl'] ?? '',
      durationMs: d['durationMs'] ?? 0,
      scheduledTime: d['scheduledTime'] is Timestamp
          ? (d['scheduledTime'] as Timestamp).toDate()
          : DateTime.now(),
      status: d['status'] ?? 'pending',
      createdAt: d['createdAt'] is Timestamp
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }
}
