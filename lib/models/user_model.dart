import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String email;
  final String name;
  final String bio;
  final String? partnerId;
  final String? partnerEmail;
  final String? coupleId;
  final bool isOnline;
  final DateTime? lastSeen;
  final int streakCount;
  final List<String> blockedUsers;
  final String? fcmToken;

  AppUser({
    required this.uid,
    required this.email,
    required this.name,
    required this.bio,
    this.partnerId,
    this.partnerEmail,
    this.coupleId,
    this.isOnline = false,
    this.lastSeen,
    this.streakCount = 0,
    this.blockedUsers = const [],
    this.fcmToken,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'bio': bio,
      'partnerId': partnerId,
      'partnerEmail': partnerEmail,
      'coupleId': coupleId,
      'isOnline': isOnline,
      'lastSeen': lastSeen,
      'streakCount': streakCount,
      'blockedUsers': blockedUsers,
      'fcmToken': fcmToken,
    };
  }

  factory AppUser.fromMap(Map<String, dynamic> map) {
    final blockedRaw = map['blockedUsers'];
    final blocked = blockedRaw is List
        ? blockedRaw.map((e) => e.toString()).toList()
        : <String>[];

    DateTime? lastSeen;
    final rawLastSeen = map['lastSeen'];
    if (rawLastSeen is DateTime) {
      lastSeen = rawLastSeen;
    } else if (rawLastSeen is Timestamp) {
      lastSeen = rawLastSeen.toDate();
    } else if (rawLastSeen is Map && rawLastSeen.containsKey('_seconds')) {
      // Defensive decode for some serialized Timestamp shapes.
      final seconds = rawLastSeen['_seconds'];
      if (seconds is int) {
        lastSeen = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
    }

    return AppUser(
      uid: map['uid'],
      email: map['email'],
      name: map['name'] ?? '',
      bio: map['bio'] ?? '',
      partnerId: map['partnerId'],
      partnerEmail: map['partnerEmail'],
      coupleId: map['coupleId'],
      isOnline: map['isOnline'] == true,
      lastSeen: lastSeen,
      streakCount: (map['streakCount'] is int) ? map['streakCount'] as int : 0,
      blockedUsers: blocked,
      fcmToken: map['fcmToken'],
    );
  }
}
