import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/wake_request_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> sendWakeRequest(WakeRequest request) async {
    await _db.collection('wake_requests').add(request.toMap());
  }
}
