class FriendRequest {
  final String fromUid;
  final String toUid;
  final String status;

  FriendRequest({
    required this.fromUid,
    required this.toUid,
    required this.status,
  });

  Map<String, dynamic> toMap() {
    return {
      'fromUid': fromUid,
      'toUid': toUid,
      'status': status,
    };
  }
}
