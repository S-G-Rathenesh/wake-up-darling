import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../widgets/romantic_hearts_overlay.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import '../services/alarm_service.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/wake_stats_service.dart';

class AlarmScreen extends StatefulWidget {
  /// Notification ID used to cancel the alarm and match the Firestore record.
  final int alarmId;

  /// Couple document ID used for the remote-cancel Firestore listener.
  final String coupleId;

  /// Optional voice URL for voice-wake playback (overrides default alarm sound).
  final String voiceUrl;

  const AlarmScreen({
    super.key,
    this.alarmId = 0,
    this.coupleId = '',
    this.voiceUrl = '',
  });

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  final AudioPlayer _player = AudioPlayer();
  final AuthService _auth = AuthService();
  final UserService _userService = UserService();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _cancelSub;
  Timer? _ignoreTimer;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    _startAlarm();
    _markRinging();
    _registerRemoteCancelListener();
    // If alarm is ignored for 60 s → record as missed and reset streak.
    _ignoreTimer = Timer(const Duration(seconds: 60), () {
      if (!_stopping) {
        WakeStatsService.recordIgnored(coupleId: widget.coupleId)
            .catchError((_) {});
      }
    });
  }

  /// Tell Firestore that this alarm is now actively ringing.
  Future<void> _markRinging() async {
    await AlarmService.updateCoupleAlarmStatus(
      coupleId: widget.coupleId,
      status: 'ringing',
    );
  }

  /// Listen to the couple document; if the alarm is remotely cancelled, stop.
  void _registerRemoteCancelListener() {
    if (widget.coupleId.isEmpty) return;

    _cancelSub = AlarmService.streamCoupleDoc(widget.coupleId).listen(
      (snap) {
        if (!mounted || _stopping) return;
        final data = snap.data();
        if (data == null) return;
        final alarm = data['alarm'] as Map<String, dynamic>?;
        if (alarm == null) return;
        final id = alarm['id'];
        final status = alarm['status']?.toString() ?? '';
        // Match by ID when present; fall back to status-only check when alarmId == 0.
        final idMatch =
            widget.alarmId == 0 || id == null || id == widget.alarmId;
        if (status == 'cancelled' && idMatch) {
          _stopAlarm(remoteCancel: true);
        }
      },
      onError: (_) {},
    );
  }

  Future<void> _startAlarm() async {
    try {
      // Check for voice-wake URL: either passed directly or fetched from Firestore.
      String voiceUrl = widget.voiceUrl;

      if (voiceUrl.isEmpty && widget.coupleId.isNotEmpty) {
        // Try fetching voiceUrl from the couple doc's voiceWake field.
        try {
          final coupleDoc = await FirebaseFirestore.instance
              .collection('couples')
              .doc(widget.coupleId)
              .get();
          final data = coupleDoc.data();
          final voiceWake = data?['voiceWake'] as Map<String, dynamic>?;
          if (voiceWake != null && voiceWake['status'] == 'pending') {
            voiceUrl = (voiceWake['voiceUrl'] as String?) ?? '';
            debugPrint('[AlarmScreen] Fetched voiceUrl from Firestore: $voiceUrl');
          }
        } catch (e) {
          debugPrint('[AlarmScreen] Failed to fetch voiceUrl: $e');
        }
      }

      await _player.setReleaseMode(ReleaseMode.loop);
      if (voiceUrl.isNotEmpty) {
        debugPrint('[AlarmScreen] Playing voice wake URL');
        await _player.play(UrlSource(voiceUrl));
      } else {
        debugPrint('[AlarmScreen] Playing default alarm.mp3');
        await _player.play(AssetSource('alarm.mp3'));
      }
    } catch (_) {
      // If playback fails, we still show the alarm UI.
    }

    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
        Vibration.vibrate(pattern: [500, 1000], repeat: 0);
      }
    } catch (_) {
      // Ignore vibration failures.
    }
  }

  Future<void> _stopAlarm({bool remoteCancel = false}) async {
    if (_stopping) return;
    _stopping = true;
    _ignoreTimer?.cancel();

    // Cancel scheduled / active notification.
    try {
      await AlarmService.cancelAlarm(widget.alarmId);
    } catch (_) {}

    try {
      await _player.stop();
    } catch (_) {}

    try {
      Vibration.cancel();
    } catch (_) {}

    // Update couple alarm status to 'completed' (unless it was already set to
    // 'cancelled' by the creator — in that case leave it as-is).
    if (!remoteCancel) {
      await AlarmService.updateCoupleAlarmStatus(
        coupleId: widget.coupleId,
        status: 'completed',
      );
      // Record successful wake in relationship stats.
      await WakeStatsService.recordWoke(coupleId: widget.coupleId)
          .catchError((_) {});
    }

    final uidForRequests = _auth.currentUser?.uid;
    if (uidForRequests != null && uidForRequests.isNotEmpty) {
      final snapshot = await FirebaseFirestore.instance
          .collection('wake_requests')
          .where('target', isEqualTo: uidForRequests)
          .where('status', isEqualTo: 'approved')
          .get();

      for (final doc in snapshot.docs) {
        await doc.reference.update({
          'status': 'completed',
          'stoppedAt': DateTime.now(),
        });
      }
    }

    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = userDoc.data();
      final partnerUid = data?['partnerId']?.toString();
      if (partnerUid != null && partnerUid.isNotEmpty) {
        await _userService.updateStreak(partnerUid);
      }
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _cancelSub?.cancel();
    _ignoreTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.20),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite, color: Colors.white, size: 44)
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scale(
                          begin: const Offset(1.0, 1.0),
                          end: const Offset(1.25, 1.25),
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeInOut,
                        ),
                    const SizedBox(height: 12),
                    const Text(
                      'WAKE UP DARLING',
                      style: TextStyle(
                        fontSize: 22,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your love is calling you 💜',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.90),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    InkWell(
                      borderRadius: BorderRadius.circular(30),
                      onTap: _stopAlarm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            'STOP',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
                    .animate()
                    .fadeIn(
                      duration: const Duration(milliseconds: 450),
                    )
                    .scale(
                      begin: const Offset(0.95, 0.95),
                      end: const Offset(1.0, 1.0),
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOut,
                    ),
              ),
            ),
          ),
        ),
      ),
      const RomanticHeartsOverlay(),
    ],
  ),
);
  }
}
