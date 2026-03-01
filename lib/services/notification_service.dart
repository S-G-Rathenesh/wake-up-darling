import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  final _db = FirebaseFirestore.instance;

  Future<void> sendNotification(
    String toUid,
    String message, {
    String type = 'general',
  }) async {
    await _db.collection("notifications").add({
      'target': toUid,
      'message': message,
      'type': type,
      'createdAt': Timestamp.now(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getNotifications(String uid) {
    return _db
        .collection("notifications")
        .where("target", isEqualTo: uid)
        .orderBy("createdAt", descending: true)
        .snapshots();
  }
}
