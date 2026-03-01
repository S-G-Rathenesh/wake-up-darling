import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/call_model.dart';
import '../services/call_repository.dart';
import '../widgets/romantic_hearts_overlay.dart';
import 'ongoing_call_screen.dart';

/// Screen shown to the **receiver** when an incoming call is detected.
///
/// Displays the caller's name with Accept / Reject buttons.
///   - Accept → updates status to `"accepted"`, opens [OngoingCallScreen]
///   - Reject → updates status to `"rejected"`, closes screen
class IncomingCallScreen extends StatefulWidget {
  final CallModel call;

  const IncomingCallScreen({super.key, required this.call});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  final _repo = CallRepository();
  StreamSubscription? _statusSub;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    // Listen for status changes — the caller might cancel before we answer.
    _statusSub = _repo.listenCallStatus(
      callId: widget.call.id,
      onStatusChanged: (status) {
        if (!mounted || _handled) return;
        if (status == 'ended' || status == 'rejected') {
          _handled = true;
          _statusSub?.cancel();
          Navigator.pop(context);
        }
      },
    );
  }

  Future<void> _acceptCall() async {
    if (_handled) return;
    _handled = true;
    _statusSub?.cancel();

    await _repo.updateCallStatus(widget.call.id, 'accepted');

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => OngoingCallScreen(
          callId: widget.call.id,
          coupleId: widget.call.coupleId,
          partnerName: widget.call.callerName,
          type: widget.call.type,
          isCaller: false,
        ),
      ),
    );
  }

  Future<void> _rejectCall() async {
    if (_handled) return;
    _handled = true;
    _statusSub?.cancel();

    await _repo.updateCallStatus(widget.call.id, 'rejected');
    // Clean up the call document.
    await _repo.deleteCallDocument(widget.call.id, widget.call.coupleId);

    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.call.type == 'video';
    final callerName = widget.call.callerName.isNotEmpty
        ? widget.call.callerName
        : 'Partner';

    return Scaffold(
      body: Stack(
        children: [
          // ── Gradient background ──────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
              ),
            ),
          ),
          const RomanticHeartsOverlay(),

          SafeArea(
            child: Column(
              children: [
                const Spacer(),

                // ── Caller avatar ──────────────────────────────────────
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.2),
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
                      end: const Offset(1.1, 1.1),
                      duration: 1200.ms,
                    ),
                const SizedBox(height: 24),

                // ── Caller name ────────────────────────────────────────
                Text(
                  callerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // ── Call type label ────────────────────────────────────
                Text(
                  isVideo
                      ? '📹 Incoming Video Call...'
                      : '📞 Incoming Voice Call...',
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

                // ── Accept / Reject buttons ────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 50),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Reject
                      _circleButton(
                        icon: Icons.call_end,
                        color: Colors.redAccent,
                        label: 'Reject',
                        onTap: _rejectCall,
                      ),
                      // Accept
                      _circleButton(
                        icon: isVideo ? Icons.videocam : Icons.call,
                        gradient: const [Color(0xFF69F0AE), Color(0xFF00C853)],
                        label: 'Accept',
                        onTap: _acceptCall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 60),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    Color? color,
    List<Color>? gradient,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: gradient == null ? color : null,
              gradient:
                  gradient != null ? LinearGradient(colors: gradient) : null,
            ),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
