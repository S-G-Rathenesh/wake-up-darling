import 'package:cloud_firestore/cloud_firestore.dart';

class WakeRequest {
  final String createdBy;
  final String target;
  final DateTime scheduledTime;
  final String status;
  final DateTime createdAt;

  WakeRequest({
    required this.createdBy,
    required this.target,
    required this.scheduledTime,
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'createdBy': createdBy,
      'target': target,
      'scheduledTime': Timestamp.fromDate(scheduledTime),
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
