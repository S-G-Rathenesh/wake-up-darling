import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/call_limit_service.dart';
import '../services/call_repository.dart';
import '../services/zego_call_service.dart';
import '../widgets/romantic_hearts_overlay.dart';
import '../widgets/voice_wave_bars.dart';

/// Screen shown when a call is **accepted** and in progress.
///
/// Uses [ZegoCallService] for real audio/video via ZEGOCLOUD Express Engine.
class OngoingCallScreen extends StatefulWidget {
  final String callId;
  final String coupleId;
  final String partnerId;
  final String partnerName;
  final String type; // 'voice' or 'video'
  final bool isCaller;

  const OngoingCallScreen({
    super.key,
    required this.callId,
    required this.coupleId,
    required this.partnerId,
    required this.partnerName,
    required this.type,
    required this.isCaller,
  });

  @override
  State<OngoingCallScreen> createState() => _OngoingCallScreenState();
}

class _OngoingCallScreenState extends State<OngoingCallScreen> {
  final _repo = CallRepository();
  StreamSubscription? _statusSub;
  Timer? _timer;
  Timer? _limitTimer;

  Duration _duration = Duration.zero;
  bool _isMuted = false;
  bool _isSpeaker = false;
  bool _isCameraOff = false;
  bool _callActive = true;
  bool _isVideoCall = false;

  // ── Call-limit state ────────────────────────────────────────────────
  int _remainingSeconds = -1; // -1 = not yet loaded

  // ── Zego video widgets ──────────────────────────────────────────────
  Widget? _localView;

  @override
  void initState() {
    super.initState();
    _isVideoCall = widget.type == 'video';
    _initCall();

    // Start the call timer.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _duration += const Duration(seconds: 1));
    });

    // Listen for status changes (other side ending the call).
    _statusSub = _repo.listenCallStatus(
      callId: widget.callId,
      onStatusChanged: (status) {
        if (!mounted || !_callActive) return;
        if (status == 'ended' || status == 'rejected') {
          _callActive = false;
          _statusSub?.cancel();
          _timer?.cancel();
          _limitTimer?.cancel();
          _cleanup();
          if (mounted) Navigator.pop(context);
        }
      },
    );
  }

  Future<void> _initCall() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final userName = widget.partnerName.isNotEmpty ? 'User' : 'User';

    // ── Load call limit info ─────────────────────────────────────────
    if (uid.isNotEmpty) {
      _remainingSeconds = await CallLimitService.getRemainingSeconds(
        widget.coupleId,
        _isVideoCall,
      );

      if (_remainingSeconds <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Daily call limit reached'),
              backgroundColor: Colors.redAccent,
            ),
          );
          Navigator.pop(context);
        }
        return;
      }

      // Start countdown timer that auto-ends the call.
      _limitTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _remainingSeconds--);
        if (_remainingSeconds <= 0) {
          _limitTimer?.cancel();
          _endCall(limitReached: true);
        }
      });
    }

    // ── Request permissions ──────────────────────────────────────────
    final granted =
        await ZegoCallService.requestPermissions(isVideo: _isVideoCall);
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isVideoCall
                ? 'Camera & mic permissions required'
                : 'Microphone permission required'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    // ── Join Zego room ───────────────────────────────────────────────
    // CRITICAL: Use coupleId as roomID so both users join the SAME room
    final roomID = widget.coupleId;
    final joined = await ZegoCallService.joinRoom(
      roomID: roomID,
      userID: uid.isNotEmpty ? uid : 'anon_${DateTime.now().millisecondsSinceEpoch}',
      userName: userName,
      isVideo: _isVideoCall,
    );

    if (!joined) {
      debugPrint('[OngoingCall] Failed to join Zego room');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Failed to start ${_isVideoCall ? "video" : "voice"} call'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    // ── Start local preview (video calls) ────────────────────────────
    if (_isVideoCall) {
      _localView = await ZegoCallService.createLocalPreview();
      if (mounted) setState(() {});
    }

    // ── Start publishing stream ──────────────────────────────────────
    // Must be called AFTER preview for video calls, but can be called
    // immediately for voice calls
    await ZegoCallService.startPublishing(uid);
    debugPrint('[OngoingCall] Started publishing stream for ${_isVideoCall ? "video" : "voice"} call');

    debugPrint(
        '[OngoingCall] Zego call initialized (video=$_isVideoCall, room=$roomID)');
  }

  Future<void> _cleanup() async {
    // Save usage per couple.
    if (widget.coupleId.isNotEmpty && _duration.inSeconds > 0) {
      await CallLimitService.addCallUsage(
        widget.coupleId,
        _isVideoCall,
        _duration.inSeconds,
      );
    }
    await ZegoCallService.dispose();
  }

  Future<void> _endCall({bool limitReached = false}) async {
    if (!_callActive) return;
    _callActive = false;
    _statusSub?.cancel();
    _timer?.cancel();
    _limitTimer?.cancel();

    // Pop immediately — don't wait for Firestore.
    if (mounted) {
      if (limitReached) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Daily call limit reached — call ended'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
      Navigator.pop(context);
    }

    // Fire-and-forget cleanup.
    _cleanup();
    _repo.endAndCleanup(widget.callId, widget.coupleId);
  }

  void _toggleMic() {
    setState(() => _isMuted = !_isMuted);
    ZegoCallService.toggleMute(_isMuted);
  }

  void _toggleSpeaker() {
    setState(() => _isSpeaker = !_isSpeaker);
    ZegoCallService.toggleSpeaker(_isSpeaker);
  }

  void _toggleCamera() {
    setState(() => _isCameraOff = !_isCameraOff);
    ZegoCallService.toggleCamera(_isCameraOff);
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _timer?.cancel();
    _limitTimer?.cancel();
    if (_callActive) {
      _callActive = false;
      ZegoCallService.dispose();
    }
    super.dispose();
  }

  String get _formattedDuration {
    final m = _duration.inMinutes.toString().padLeft(2, '0');
    final s = (_duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _formattedRemaining {
    if (_remainingSeconds < 0) return '';
    final m = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Background ───────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A0A2E), Color(0xFF2A1B3D)],
              ),
            ),
          ),
          // Remote video (full screen) for video calls.
          if (_isVideoCall)
            Positioned.fill(
              child: ValueListenableBuilder<bool>(
                valueListenable: ZegoCallService.remoteStreamReady,
                builder: (_, ready, __) {
                  if (ready && ZegoCallService.remoteViewWidget != null) {
                    return ZegoCallService.remoteViewWidget!;
                  }
                  return const Center(
                    child: Text(
                      'Waiting for partner...',
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                  );
                },
              ),
            ),
          if (!_isVideoCall) const RomanticHeartsOverlay(),
          // Local video PiP for video calls.
          if (_isVideoCall && _localView != null)
            Positioned(
              right: 16,
              top: MediaQuery.of(context).padding.top + 16,
              width: 100,
              height: 150,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _localView!,
              ),
            ),

          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 40),

                  // ── Remaining time badge ───────────────────────────────
                  if (_remainingSeconds >= 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _remainingSeconds <= 60
                            ? Colors.redAccent.withValues(alpha: 0.8)
                            : Colors.black54,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '⏳ $_formattedRemaining left',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  if (_remainingSeconds >= 0) const SizedBox(height: 8),

                  // ── Partner avatar (voice calls only) ─────────────────
                  if (!_isVideoCall) ...[
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Partner name ───────────────────────────────────────
                  Text(
                    widget.partnerName.isNotEmpty
                        ? widget.partnerName
                        : 'Partner',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ── Timer ──────────────────────────────────────────────
                  Text(
                    '🟢 $_formattedDuration',
                    style: const TextStyle(
                      color: Color(0xFF69F0AE),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Voice wave bars (voice calls only) ────────────
                  if (!_isVideoCall)
                    const VoiceWaveBars(
                      color: Colors.purpleAccent,
                      barWidth: 5,
                      maxHeight: 45,
                      barCount: 5,
                    ),

                  const Spacer(),

                  // ── Control buttons ────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Mic toggle
                        _controlButton(
                          icon: _isMuted ? Icons.mic_off : Icons.mic,
                          color: _isMuted ? Colors.redAccent : Colors.white24,
                          label: _isMuted ? 'Unmute' : 'Mute',
                          onTap: _toggleMic,
                        ),

                        // Speaker toggle
                        _controlButton(
                          icon: _isSpeaker
                              ? Icons.volume_up
                              : Icons.volume_down,
                          color: _isSpeaker ? Colors.purple : Colors.white24,
                          label: _isSpeaker ? 'Earpiece' : 'Speaker',
                          onTap: _toggleSpeaker,
                        ),

                        // Camera toggle (video calls only)
                        if (_isVideoCall)
                          _controlButton(
                            icon: _isCameraOff
                                ? Icons.videocam_off
                                : Icons.videocam,
                            color: _isCameraOff
                                ? Colors.redAccent
                                : Colors.white24,
                            label: _isCameraOff ? 'Cam On' : 'Cam Off',
                            onTap: _toggleCamera,
                          ),

                        // Switch front/back camera (video calls only)
                        if (_isVideoCall)
                          _controlButton(
                            icon: Icons.cameraswitch,
                            color: Colors.white24,
                            label: 'Flip',
                            onTap: () => ZegoCallService.switchCamera(),
                          ),

                        // End call (large red button)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                            const SizedBox(height: 6),
                            Text(
                              'End',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
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

  Widget _controlButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
