import 'package:flutter/material.dart';

import '../../chat_screen_v2.dart';

/// Chat sub-tab inside the Couple Dashboard.
/// Embeds [ChatScreenV2] directly (no separate Scaffold).
class CoupleChat extends StatelessWidget {
  final String coupleId;
  final String partnerId;
  final String partnerName;

  const CoupleChat({
    super.key,
    required this.coupleId,
    required this.partnerId,
    required this.partnerName,
  });

  @override
  Widget build(BuildContext context) {
    if (partnerId.isEmpty) {
      return Center(
        child: Text(
          'Waiting for partner info…',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        ),
      );
    }

    return ChatScreenV2(
      coupleId: coupleId,
      partnerId: partnerId,
      partnerName: partnerName,
      embedded: true,
    );
  }
}
