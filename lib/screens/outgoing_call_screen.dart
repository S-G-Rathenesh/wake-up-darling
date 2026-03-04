import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/call_repository.dart';
import '../widgets/romantic_hearts_overlay.dart';
import 'ongoing_call_screen.dart';

/// Screen shown to the **caller** after initiating a call.
///
/// Displays "Calling..." with an end-call button.
/// Listens for status changes on the Firestore call document:
///   - `"accepted"` → navigates to [OngoingCallScreen]
///   - `"rejected"` or `"ended"` → closes this screen
class OutgoingCallScreen extends StatefulWidget {
  final String callId;
  final String coupleId;
  final String receiverId;
  final String receiverName;
  final String type; // 'voice' or 'video'

  const OutgoingCallScreen({
    super.key,
    required this.callId,
    required this.coupleId,
    required this.receiverId,
    required this.receiverName,
    required this.type,
  });

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen> {
  final _repo = CallRepository();
  StreamSubscription? _statusSub;
  String _currentStatus = 'calling';

  @override
  void initState() {
    super.initState();
    _listenCallStatus();
  }

  void _listenCallStatus() {
    _statusSub = _repo.listenCallStatus(
      callId: widget.callId,
      onStatusChanged: (status) {
        if (!mounted) return;

        setState(() => _currentStatus = status);

        if (status == 'accepted') {
          // Navigate to ongoing call screen.
          _statusSub?.cancel();
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => OngoingCallScreen(
                callId: widget.callId,
                coupleId: widget.coupleId,
                partnerId: widget.receiverId,
                partnerName: widget.receiverName,
                type: widget.type,
                isCaller: true,
              ),
            ),
          );
        } else if (status == 'rejected' || status == 'ended') {
          // Other side rejected or call ended.
          _statusSub?.cancel();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(status == 'rejected'
                    ? 'Call was rejected'
                    : 'Call ended'),
                backgroundColor: Colors.redAccent,
              ),
            );
            Navigator.pop(context);
          }
        }
      },
    );
  }

  Future<void> _endCall() async {
    _statusSub?.cancel();
    // Pop immediately so the user doesn't wait for Firestore round-trips.
    if (mounted) Navigator.pop(context);
    // Fire-and-forget cleanup.
    _repo.endAndCleanup(widget.callId, widget.coupleId);
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.type == 'video';

    return Scaffold(
      body: Stack(
        children: [
          // ── Gradient background ──────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A0A2E), Color(0xFF2A1B3D)],
              ),
            ),
          ),
          const RomanticHeartsOverlay(),

          Positioned.fill(
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(),

                // ── Partner avatar ─────────────────────────────────────
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.purple.withValues(alpha: 0.4),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    isVideo ? Icons.videocam : Icons.person,
                    color: Colors.white,
                    size: 60,
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(
                      begin: const Offset(1, 1),
                      end: const Offset(1.08, 1.08),
                      duration: 1200.ms,
                    ),
                const SizedBox(height: 24),

                // ── Partner name ───────────────────────────────────────
                Text(
                  widget.receiverName.isNotEmpty
                      ? widget.receiverName
                      : 'Partner',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                // ── Status text ────────────────────────────────────────
                Text(
                  _currentStatus == 'calling'
                      ? (isVideo ? '📹 Calling...' : '📞 Calling...')
                      : _currentStatus == 'accepted'
                          ? '🟢 Connected!'
                          : '⏳ $_currentStatus',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 16,
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .fadeIn(duration: 800.ms)
                    .then()
                    .fadeOut(duration: 800.ms),

                const Spacer(),

                // ── End call button ────────────────────────────────────
                GestureDetector(
                  onTap: _endCall,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.redAccent,
                    ),
                    child: const Icon(
                      Icons.call_end,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'End Call',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 60),
              ],
            ),
          ),
          ),
        ],
      ),
    );
  }
}
