import 'package:cloud_firestore/cloud_firestore.dart';

/// Call signaling record stored in `Calls/{callId}`.
///
/// Firestore structure:
/// ```
/// Calls/{callId}
///   callerId: String
///   callerName: String
///   receiverId: String
///   receiverName: String
///   coupleId: String
///   type: "voice" | "video"
///   status: "calling" | "accepted" | "rejected" | "ended"
///   timestamp: serverTimestamp
///   endedAt: serverTimestamp (set when ended/rejected)
/// ```
class CallModel {
  final String id;
  final String callerId;
  final String callerName;
  final String receiverId;
  final String receiverName;
  final String coupleId;
  final String type;    // 'voice' | 'video'
  final String status;  // 'calling' | 'accepted' | 'rejected' | 'ended'
  final DateTime timestamp;
  final DateTime? endedAt;

  CallModel({
    required this.id,
    required this.callerId,
    this.callerName = '',
    required this.receiverId,
    this.receiverName = '',
    this.coupleId = '',
    required this.type,
    this.status = 'calling',
    required this.timestamp,
    this.endedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'callerId': callerId,
      'callerName': callerName,
      'receiverId': receiverId,
      'receiverName': receiverName,
      'coupleId': coupleId,
      'type': type,
      'status': status,
      'timestamp': Timestamp.fromDate(timestamp),
      if (endedAt != null) 'endedAt': Timestamp.fromDate(endedAt!),
    };
  }

  factory CallModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return CallModel(
      id: doc.id,
      callerId: d['callerId'] ?? '',
      callerName: d['callerName'] ?? '',
      receiverId: d['receiverId'] ?? '',
      receiverName: d['receiverName'] ?? '',
      coupleId: d['coupleId'] ?? '',
      type: d['type'] ?? 'voice',
      status: d['status'] ?? 'calling',
      timestamp: d['timestamp'] is Timestamp
          ? (d['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      endedAt: d['endedAt'] is Timestamp
          ? (d['endedAt'] as Timestamp).toDate()
          : null,
    );
  }

  CallModel copyWith({String? status, DateTime? endedAt}) {
    return CallModel(
      id: id,
      callerId: callerId,
      callerName: callerName,
      receiverId: receiverId,
      receiverName: receiverName,
      coupleId: coupleId,
      type: type,
      status: status ?? this.status,
      timestamp: timestamp,
      endedAt: endedAt ?? this.endedAt,
    );
  }
}
