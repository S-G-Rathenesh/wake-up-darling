import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../services/call_limit_service.dart';
import '../../../services/call_repository.dart';
import '../../outgoing_call_screen.dart';
import '../../voice_wake_screen.dart';

/// Calls sub-tab inside the Couple Dashboard.
/// Shows voice/video call buttons and a voice wake option.
class CoupleCalls extends StatelessWidget {
  final String coupleId;
  final String partnerId;
  final String partnerName;

  const CoupleCalls({
    super.key,
    required this.coupleId,
    required this.partnerId,
    required this.partnerName,
  });

  /// Request microphone (and camera for video) permissions before calling.
  Future<bool> _requestCallPermissions(
      BuildContext context, bool isVideo) async {
    final permissions = <Permission>[Permission.microphone];
    if (isVideo) permissions.add(Permission.camera);

    final statuses = await permissions.request();
    final allGranted = statuses.values.every(
      (s) => s == PermissionStatus.granted,
    );

    if (!allGranted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isVideo
              ? 'Camera & microphone permissions are required for video calls'
              : 'Microphone permission is required for voice calls'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
    return allGranted;
  }

  Future<void> _startCall(
      BuildContext context, String type, bool isVideo) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty || partnerId.isEmpty) return;

    // ── Check daily call limit ───────────────────────────────────────
    final allowed = await CallLimitService.canStartCall(coupleId, isVideo);

    if (!allowed && context.mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF2A1B3D),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Daily Limit Reached',
              style: TextStyle(color: Colors.white)),
          content: Text(
            isVideo
                ? 'Video call limit (${CallLimitService.maxVideoMinutesPerDay} minutes/day) reached.'
                : 'Voice call limit (${CallLimitService.maxVoiceMinutesPerDay} minutes/day) reached.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK',
                  style: TextStyle(color: Colors.purpleAccent)),
            ),
          ],
        ),
      );
      return;
    }

    // Request runtime permissions before starting the call.
    final granted = await _requestCallPermissions(context, isVideo);
    if (!granted || !context.mounted) return;

    final currentName = (await FirebaseFirestore.instance
                .collection('users')
                .doc(currentUid)
                .get())
            .data()?['name']
            ?.toString() ??
        'You';

    final repo = CallRepository();
    final callId = await repo.startCall(
      callerId: currentUid,
      callerName: currentName,
      receiverId: partnerId,
      receiverName: partnerName,
      coupleId: coupleId,
      type: type,
    );

    if (!context.mounted) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => OutgoingCallScreen(
          callId: callId,
          coupleId: coupleId,
          receiverName: partnerName,
          type: type,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          // ── Voice Call ─────────────────────────────────────────────
          _callCard(
            context: context,
            icon: Icons.call,
            title: 'Voice Call 📞',
            subtitle: 'Start a romantic voice call',
            gradient: const [Color(0xFF7C4DFF), Color(0xFFE040FB)],
            onTap: () => _startCall(context, 'voice', false),
          ),
          const SizedBox(height: 16),

          // ── Video Call ─────────────────────────────────────────────
          _callCard(
            context: context,
            icon: Icons.videocam,
            title: 'Video Call 📹',
            subtitle: 'See your partner\'s smile',
            gradient: const [Color(0xFFE040FB), Color(0xFFFF6B6B)],
            onTap: () => _startCall(context, 'video', true),
          ),
          const SizedBox(height: 16),

          // ── Voice Wake ─────────────────────────────────────────────
          _callCard(
            context: context,
            icon: Icons.mic,
            title: 'Voice Wake 🎙️',
            subtitle: 'Record your voice to wake partner',
            gradient: const [Color(0xFF6A11CB), Color(0xFF7C4DFF)],
            onTap: () {
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => VoiceWakeScreen(
                    coupleId: coupleId,
                    partnerId: partnerId,
                    partnerName: partnerName,
                  ),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                  transitionDuration: const Duration(milliseconds: 300),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _callCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.20),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                color: Colors.white.withValues(alpha: 0.5), size: 18),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.05, end: 0);
  }
}
