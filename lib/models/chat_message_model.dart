import 'package:cloud_firestore/cloud_firestore.dart';

/// Message types supported in the chat system.
enum MessageType { text, image, voice, oneTime }

/// Read‐receipt status for a message.
enum ReadStatus { sent, delivered, read }

/// A single chat message stored in
/// `Chats/{coupleId}/Messages/{messageId}`.
class ChatMessage {
  final String id;
  final String senderId;
  final String receiverId;
  final String coupleId;
  final MessageType messageType;
  final String text;
  final String? mediaUrl;
  final String? imageData;              // base64 encoded (one-time images only)
  final String? localPath;               // private app storage path
  final String? mediaMimeType;
  final int? mediaDurationMs;           // voice note duration
  final ReadStatus readStatus;
  final bool deliveredStatus;
  final DateTime timestamp;
  final DateTime? editedAt;             // non-null when message was edited
  final bool deletedForEveryone;
  final List<String> deletedForMeList;  // UIDs that deleted this msg locally
  final String? replyToMessageId;       // id of the message being replied to
  final String? replyToText;            // preview text of the replied message
  final String? replyToSenderId;
  final Map<String, String> reactions;  // uid → emoji
  final bool isOneTimeViewed;           // for oneTime images
  final List<String> oneTimeViewedBy;   // UIDs who already viewed
  final bool isDeleted;                 // media deleted from storage

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.coupleId,
    required this.messageType,
    this.text = '',
    this.mediaUrl,
    this.imageData,
    this.localPath,
    this.mediaMimeType,
    this.mediaDurationMs,
    this.readStatus = ReadStatus.sent,
    this.deliveredStatus = false,
    required this.timestamp,
    this.editedAt,
    this.deletedForEveryone = false,
    this.deletedForMeList = const [],
    this.replyToMessageId,
    this.replyToText,
    this.replyToSenderId,
    this.reactions = const {},
    this.isOneTimeViewed = false,
    this.oneTimeViewedBy = const [],
    this.isDeleted = false,
  });

  // ── Serialisation ──────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'coupleId': coupleId,
      'messageType': messageType.name,
      'text': text,
      'mediaUrl': mediaUrl,
      'imageData': imageData,
      'localPath': localPath,
      'mediaMimeType': mediaMimeType,
      'mediaDurationMs': mediaDurationMs,
      'readStatus': readStatus.name,
      'deliveredStatus': deliveredStatus,
      'timestamp': Timestamp.fromDate(timestamp),
      'editedAt': editedAt != null ? Timestamp.fromDate(editedAt!) : null,
      'deletedForEveryone': deletedForEveryone,
      'deletedForMeList': deletedForMeList,
      'replyToMessageId': replyToMessageId,
      'replyToText': replyToText,
      'replyToSenderId': replyToSenderId,
      'reactions': reactions,
      'isOneTimeViewed': isOneTimeViewed,
      'oneTimeViewedBy': oneTimeViewedBy,
      'isDeleted': isDeleted,
    };
  }

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ChatMessage(
      id: doc.id,
      senderId: d['senderId'] ?? '',
      receiverId: d['receiverId'] ?? '',
      coupleId: d['coupleId'] ?? '',
      messageType: MessageType.values.firstWhere(
        (e) => e.name == (d['messageType'] ?? 'text'),
        orElse: () => MessageType.text,
      ),
      text: d['text'] ?? '',
      mediaUrl: d['mediaUrl'],
      imageData: d['imageData'],
      localPath: d['localPath'],
      mediaMimeType: d['mediaMimeType'],
      mediaDurationMs: d['mediaDurationMs'],
      readStatus: ReadStatus.values.firstWhere(
        (e) => e.name == (d['readStatus'] ?? 'sent'),
        orElse: () => ReadStatus.sent,
      ),
      deliveredStatus: d['deliveredStatus'] == true,
      timestamp: d['timestamp'] is Timestamp
          ? (d['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      editedAt: d['editedAt'] is Timestamp
          ? (d['editedAt'] as Timestamp).toDate()
          : null,
      deletedForEveryone: d['deletedForEveryone'] == true,
      deletedForMeList: (d['deletedForMeList'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      replyToMessageId: d['replyToMessageId'],
      replyToText: d['replyToText'],
      replyToSenderId: d['replyToSenderId'],
      reactions: (d['reactions'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          {},
      isOneTimeViewed: d['isOneTimeViewed'] == true,
      oneTimeViewedBy: (d['oneTimeViewedBy'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      isDeleted: d['isDeleted'] == true,
    );
  }

  /// Whether this message should be visible to the given UID.
  bool isVisibleTo(String uid) {
    if (deletedForEveryone) return false;
    if (deletedForMeList.contains(uid)) return false;
    return true;
  }

  /// Whether the message can still be edited (within 5 minutes).
  bool canEdit(String uid) {
    if (senderId != uid) return false;
    if (deletedForEveryone) return false;
    final diff = DateTime.now().difference(timestamp);
    return diff.inMinutes < 5;
  }

  ChatMessage copyWith({
    String? id,
    String? text,
    String? localPath,
    ReadStatus? readStatus,
    bool? deliveredStatus,
    bool? deletedForEveryone,
    List<String>? deletedForMeList,
    Map<String, String>? reactions,
    DateTime? editedAt,
    bool? isOneTimeViewed,
    List<String>? oneTimeViewedBy,
    bool? isDeleted,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId,
      receiverId: receiverId,
      coupleId: coupleId,
      messageType: messageType,
      text: text ?? this.text,
      mediaUrl: mediaUrl,
      imageData: imageData,
      localPath: localPath ?? this.localPath,
      mediaMimeType: mediaMimeType,
      mediaDurationMs: mediaDurationMs,
      readStatus: readStatus ?? this.readStatus,
      deliveredStatus: deliveredStatus ?? this.deliveredStatus,
      timestamp: timestamp,
      editedAt: editedAt ?? this.editedAt,
      deletedForEveryone: deletedForEveryone ?? this.deletedForEveryone,
      deletedForMeList: deletedForMeList ?? this.deletedForMeList,
      replyToMessageId: replyToMessageId,
      replyToText: replyToText,
      replyToSenderId: replyToSenderId,
      reactions: reactions ?? this.reactions,
      isOneTimeViewed: isOneTimeViewed ?? this.isOneTimeViewed,
      oneTimeViewedBy: oneTimeViewedBy ?? this.oneTimeViewedBy,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
