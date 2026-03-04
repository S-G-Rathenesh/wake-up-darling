import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/chat_message_model.dart';
import 'cloudinary_service.dart';
import 'local_media_service.dart';

/// Full‐featured couple chat service backed by Firestore & local storage.
///
/// Firestore layout:
///   Chats/{coupleId}/Messages/{messageId}
///   UserStatus/{uid}   – typing, online, lastSeen
class ChatService {
  ChatService({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get _myUid => _auth.currentUser?.uid ?? '';

  // ─── Collection references ────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _messagesCol(String coupleId) =>
      _db.collection('Chats').doc(coupleId).collection('Messages');

  DocumentReference<Map<String, dynamic>> _userStatusRef(String uid) =>
      _db.collection('UserStatus').doc(uid);

  // ─── Send text message ────────────────────────────────────────────────────

  Future<void> sendTextMessage({
    required String coupleId,
    required String receiverId,
    required String text,
    String? replyToMessageId,
    String? replyToText,
    String? replyToSenderId,
  }) async {
    final msg = ChatMessage(
      id: '',
      senderId: _myUid,
      receiverId: receiverId,
      coupleId: coupleId,
      messageType: MessageType.text,
      text: text,
      timestamp: DateTime.now(),
      replyToMessageId: replyToMessageId,
      replyToText: replyToText,
      replyToSenderId: replyToSenderId,
    );
    await _messagesCol(coupleId).add(msg.toMap());
  }

  // ─── Send image ───────────────────────────────────────────────────────────

  Future<void> sendImageMessage({
    required String coupleId,
    required String receiverId,
    required File imageFile,
    bool isOneTime = false,
  }) async {
    // One-time images use base64 storage (no cloud upload)
    if (isOneTime) {
      return sendOneTimeImage(
        coupleId: coupleId,
        receiverId: receiverId,
        imageFile: imageFile,
      );
    }

    try {
      debugPrint('[ChatService] Uploading image to Cloudinary...');
      final url = await CloudinaryService().uploadFile(imageFile);
      
      // Strict validation: ensure URL is valid HTTPS
      if (url.isEmpty || !url.startsWith('https://')) {
        throw Exception('Invalid mediaUrl returned: $url');
      }
      debugPrint('[ChatService] Image uploaded successfully: $url');

      final msg = ChatMessage(
        id: '',
        senderId: _myUid,
        receiverId: receiverId,
        coupleId: coupleId,
        messageType: MessageType.image,
        mediaUrl: url,
        mediaMimeType: 'image/${imageFile.path.split('.').last}',
        timestamp: DateTime.now(),
        isDeleted: false,
      );
      await _messagesCol(coupleId).add(msg.toMap());
    } catch (e) {
      debugPrint('[ChatService] sendImageMessage failed: $e');
      // DO NOT send message if upload failed
      rethrow;
    }
  }

  // ─── Send one-time image (base64 in Firestore, no cloud) ──────────────────

  Future<void> sendOneTimeImage({
    required String coupleId,
    required String receiverId,
    required File imageFile,
  }) async {
    try {
      debugPrint('[ChatService] Encoding one-time image as base64...');
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      debugPrint('[ChatService] One-time image encoded: ${bytes.length} bytes');

      final msg = ChatMessage(
        id: '',
        senderId: _myUid,
        receiverId: receiverId,
        coupleId: coupleId,
        messageType: MessageType.oneTime,
        imageData: base64Image,
        mediaMimeType: 'image/${imageFile.path.split('.').last}',
        timestamp: DateTime.now(),
        isDeleted: false,
      );
      await _messagesCol(coupleId).add(msg.toMap());
      debugPrint('[ChatService] One-time image stored in Firestore (no cloud upload)');
    } catch (e) {
      debugPrint('[ChatService] sendOneTimeImage failed: $e');
      rethrow;
    }
  }

  // ─── Send voice note ─────────────────────────────────────────────────────

  Future<void> sendVoiceMessage({
    required String coupleId,
    required String receiverId,
    required File audioFile,
    int durationMs = 0,
  }) async {
    // Prevent sending empty / 0-duration voice notes.
    if (durationMs <= 0) {
      debugPrint('[ChatService] Skipping voice note — duration is 0');
      return;
    }
    if (!audioFile.existsSync() || audioFile.lengthSync() == 0) {
      debugPrint('[ChatService] Skipping voice note — file missing or empty');
      return;
    }

    try {
      debugPrint('[ChatService] Uploading voice note to Cloudinary...');
      final url = await CloudinaryService().uploadFile(audioFile);
      
      // Strict validation: ensure URL is valid HTTPS
      if (url.isEmpty || !url.startsWith('https://')) {
        throw Exception('Invalid mediaUrl returned: $url');
      }
      debugPrint('[ChatService] Voice note uploaded successfully: $url');

      final msg = ChatMessage(
        id: '',
        senderId: _myUid,
        receiverId: receiverId,
        coupleId: coupleId,
        messageType: MessageType.voice,
        mediaUrl: url,
        mediaMimeType: 'audio/m4a',
        mediaDurationMs: durationMs,
        timestamp: DateTime.now(),
        isDeleted: false,
      );
      await _messagesCol(coupleId).add(msg.toMap());
    } catch (e) {
      debugPrint('[ChatService] sendVoiceMessage failed: $e');
      // DO NOT send message if upload failed
      rethrow;
    }
  }

  // ─── Stream messages (real-time) ──────────────────────────────────────────

  Stream<List<ChatMessage>> streamMessages(String coupleId) {
    return _messagesCol(coupleId)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ChatMessage.fromDoc(doc))
            // Keep deletedForEveryone messages (UI shows placeholder).
            // Only hide messages the current user explicitly deleted for self.
            .where((m) => !m.deletedForMeList.contains(_myUid))
            .toList());
  }

  // ─── Search messages ──────────────────────────────────────────────────────

  Future<List<ChatMessage>> searchMessages(
      String coupleId, String query) async {
    final q = query.toLowerCase();
    final snap = await _messagesCol(coupleId)
        .orderBy('timestamp', descending: true)
        .get();
    return snap.docs
        .map((doc) => ChatMessage.fromDoc(doc))
        .where((m) =>
            m.isVisibleTo(_myUid) && m.text.toLowerCase().contains(q))
        .toList();
  }

  // ─── Read receipts ────────────────────────────────────────────────────────

  /// Mark all unread messages sent by the other person as 'read'.
  Future<void> markMessagesAsRead(String coupleId) async {
    try {
      final snap = await _messagesCol(coupleId)
          .where('receiverId', isEqualTo: _myUid)
          .where('readStatus', isNotEqualTo: 'read')
          .get();

      if (snap.docs.isEmpty) return;

      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {
          'readStatus': ReadStatus.read.name,
          'deliveredStatus': true,
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('[ChatService] markMessagesAsRead error: $e');
    }
  }

  /// Mark messages as delivered (called on app open / FCM receive).
  Future<void> markMessagesAsDelivered(String coupleId) async {
    try {
      final snap = await _messagesCol(coupleId)
          .where('receiverId', isEqualTo: _myUid)
          .where('deliveredStatus', isEqualTo: false)
          .get();

      if (snap.docs.isEmpty) return;

      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {
          'deliveredStatus': true,
          'readStatus': ReadStatus.delivered.name,
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('[ChatService] markMessagesAsDelivered error: $e');
    }
  }

  // ─── Delete for me ────────────────────────────────────────────────────────

  Future<void> deleteForMe({
    required String coupleId,
    required String messageId,
  }) async {
    try {
      await _messagesCol(coupleId).doc(messageId).update({
        'deletedForMeList': FieldValue.arrayUnion([_myUid]),
      });
    } catch (e) {
      debugPrint('[ChatService] deleteForMe error: $e');
    }
  }

  // ─── Delete for everyone (soft‐delete flag) ──────────────────────────────

  Future<void> deleteForEveryone({
    required String coupleId,
    required String messageId,
  }) async {
    try {
      final doc = await _messagesCol(coupleId).doc(messageId).get();
      if (doc.exists) {
        // Delete local media file if present.
        final localPath = doc.data()?['localPath'] as String?;
        if (localPath != null && localPath.isNotEmpty) {
          await LocalMediaService.deletePrivateFile(localPath);
        }
      }

      await _messagesCol(coupleId).doc(messageId).update({
        'deletedForEveryone': true,
        'isDeleted': true,
        'text': '',
        'mediaUrl': null,
        'localPath': null,
      });
    } catch (e) {
      debugPrint('[ChatService] deleteForEveryone error: $e');
    }
  }

  // ─── Edit message (within 5 min) ─────────────────────────────────────────

  Future<bool> editMessage({
    required String coupleId,
    required String messageId,
    required String newText,
  }) async {
    try {
      final doc = await _messagesCol(coupleId).doc(messageId).get();
      if (!doc.exists) return false;
      final msg = ChatMessage.fromDoc(doc);
      if (!msg.canEdit(_myUid)) return false;

      await _messagesCol(coupleId).doc(messageId).update({
        'text': newText,
        'editedAt': Timestamp.fromDate(DateTime.now()),
      });
      return true;
    } catch (e) {
      debugPrint('[ChatService] editMessage error: $e');
      return false;
    }
  }

  // ─── Emoji reactions ─────────────────────────────────────────────────────

  Future<void> toggleReaction({
    required String coupleId,
    required String messageId,
    required String emoji,
  }) async {
    try {
      final doc = await _messagesCol(coupleId).doc(messageId).get();
      if (!doc.exists) return;
      final msg = ChatMessage.fromDoc(doc);
      final current = Map<String, String>.from(msg.reactions);

      if (current[_myUid] == emoji) {
        current.remove(_myUid);
      } else {
        current[_myUid] = emoji;
      }

      await _messagesCol(coupleId).doc(messageId).update({
        'reactions': current,
      });
    } catch (e) {
      debugPrint('[ChatService] toggleReaction error: $e');
    }
  }

  // ─── One-time image view ──────────────────────────────────────────────────
  // ✅ CORRECT FLOW: Display image → delete from Firestore → Cloudinary auto cleanup

  Future<void> markOneTimeViewed({
    required String coupleId,
    required String messageId,
  }) async {
    try {
      final doc = await _messagesCol(coupleId).doc(messageId).get();
      if (doc.exists) {
        // Delete local cached file if present
        final localPath = doc.data()?['localPath'] as String?;
        if (localPath != null && localPath.isNotEmpty) {
          await LocalMediaService.deletePrivateFile(localPath);
        }
      }

      // ✅ DELETE MESSAGE FROM FIRESTORE after viewing
      // This prevents the receiver from viewing again
      // Cloudinary storage is managed separately by Cloudinary
      await _messagesCol(coupleId).doc(messageId).delete();
      debugPrint('[ChatService] One-time message deleted from Firestore: $messageId');
    } catch (e) {
      debugPrint('[ChatService] markOneTimeViewed error: $e');
    }
  }

  // ─── Typing indicator ────────────────────────────────────────────────────

  Future<void> setTyping(bool typing) async {
    if (_myUid.isEmpty) return;
    try {
      await _userStatusRef(_myUid).set({
        'typing': typing,
        'lastTyping': Timestamp.now(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[ChatService] setTyping error: $e');
    }
  }

  Stream<bool> partnerTypingStream(String partnerUid) {
    return _userStatusRef(partnerUid).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return false;
      final typing = data['typing'] == true;
      if (!typing) return false;
      // Only show "typing" if the event is recent (< 10 s).
      final ts = data['lastTyping'] as Timestamp?;
      if (ts == null) return false;
      return DateTime.now().difference(ts.toDate()).inSeconds < 10;
    });
  }

  // ─── Online / last seen ──────────────────────────────────────────────────

  Future<void> setOnlineStatus(bool online) async {
    if (_myUid.isEmpty) return;
    try {
      final data = <String, dynamic>{'online': online};
      // Only update lastSeen when going offline so it reflects the actual
      // time the user left (WhatsApp-style).
      if (!online) {
        data['lastSeen'] = Timestamp.now();
      }
      await _userStatusRef(_myUid).set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[ChatService] setOnlineStatus error: $e');
    }
  }

  Stream<Map<String, dynamic>> partnerStatusStream(String partnerUid) {
    return _userStatusRef(partnerUid).snapshots().map((snap) {
      final d = snap.data() ?? {};
      return {
        'online': d['online'] == true,
        'lastSeen': d['lastSeen'] is Timestamp
            ? (d['lastSeen'] as Timestamp).toDate()
            : null,
      };
    });
  }

  // ─── Shared media gallery ────────────────────────────────────────────────

  Future<List<ChatMessage>> getSharedMedia(String coupleId) async {
    try {
      // Try compound query (requires composite index on messageType + timestamp).
      final snap = await _messagesCol(coupleId)
          .where('messageType', whereIn: ['image', 'voice'])
          .orderBy('timestamp', descending: true)
          .get();
      return snap.docs
          .map((doc) => ChatMessage.fromDoc(doc))
          .where((m) => m.isVisibleTo(_myUid) && !m.deletedForEveryone)
          .toList();
    } catch (e) {
      debugPrint('[ChatService] getSharedMedia compound query failed: $e');
      // Fallback: fetch all messages and filter client-side.
      final snap = await _messagesCol(coupleId)
          .orderBy('timestamp', descending: true)
          .get();
      return snap.docs
          .map((doc) => ChatMessage.fromDoc(doc))
          .where((m) =>
              (m.messageType == MessageType.image ||
                  m.messageType == MessageType.voice) &&
              m.isVisibleTo(_myUid) &&
              !m.deletedForEveryone)
          .toList();
    }
  }
}
