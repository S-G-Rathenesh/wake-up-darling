import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../services/user_service.dart';
import '../../services/couple_service.dart';
import '../../services/alarm_service.dart';
import '../../services/wake_stats_service.dart';
import '../../widgets/glass_card.dart';

/// The "Wake" tab — glowing heart header, welcome text, pairing UI, and
/// the core "Wake Your Partner" button with full alarm-scheduling logic.
class WakeTab extends StatefulWidget {
  final String coupleId;
  final VoidCallback onCoupleIdChanged;

  const WakeTab({
    super.key,
    required this.coupleId,
    required this.onCoupleIdChanged,
  });

  @override
  State<WakeTab> createState() => _WakeTabState();
}

class _WakeTabState extends State<WakeTab> {
  final userService = UserService();
  final coupleService = CoupleService();
  final partnerEmailController = TextEditingController();
  bool _isPairingLoading = false;

  String formatTime(DateTime time) => DateFormat('h:mm a').format(time);

  /// Returns true if current time is within college hours (08:00–17:30).
  bool isCollegeTime() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 8, 0);
    final end = DateTime(now.year, now.month, now.day, 17, 30);
    return now.isAfter(start) && now.isBefore(end);
  }

  @override
  void dispose() {
    partnerEmailController.dispose();
    super.dispose();
  }

  Widget _homeNotificationsCard(String currentUserUid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('target', isEqualTo: currentUserUid)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const SizedBox.shrink();
        final data = docs.first.data();
        final message = (data['message'] ?? '').toString();
        if (message.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          child: GlassCard(
            borderRadius: 22,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.notifications_active,
                    color: Colors.white.withValues(alpha: 0.85), size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _premiumButton(String text, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: Colors.white.withValues(alpha: 0.15),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: Colors.purpleAccent.withValues(alpha: 0.45),
                blurRadius: 25,
                spreadRadius: 2,
              ),
              const BoxShadow(
                color: Colors.black26,
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(begin: 1.0, end: 1.02, duration: 1200.ms, curve: Curves.easeInOut);
  }

  Widget _floatingHearts() {
    const positions = [
      (left: 20.0, bottom: 20.0, size: 18.0),
      (left: 80.0, bottom: 60.0, size: 28.0),
      (left: 160.0, bottom: 10.0, size: 22.0),
      (left: 260.0, bottom: 50.0, size: 16.0),
      (left: 320.0, bottom: 30.0, size: 24.0),
    ];
    return SizedBox(
      height: 120,
      child: Stack(
        children: positions.map((p) {
          return Positioned(
            left: p.left,
            bottom: p.bottom,
            child: Icon(
              Icons.favorite,
              color: Colors.white.withValues(alpha: 0.15),
              size: p.size,
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .moveY(
                  begin: 0,
                  end: -20,
                  duration:
                      Duration(milliseconds: 2000 + (p.size * 80).toInt()),
                  curve: Curves.easeInOut,
                )
                .fadeIn(duration: 600.ms),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userService.getCurrentUserProfile(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? <String, dynamic>{};
        final name = (data['name'] ?? 'Welcome 💜').toString();
        final partnerId = data['partnerId'];
        final partnerEmail = (data['partnerEmail'] ?? '').toString();

        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    // ── Glowing heart header ────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.30),
                            Colors.transparent,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.15),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.favorite,
                        size: 60,
                        color: Colors.white,
                      ),
                    )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scale(
                          duration: 1800.ms,
                          begin: const Offset(1.0, 1.0),
                          end: const Offset(1.08, 1.08),
                          curve: Curves.easeInOut,
                        ),
                    const SizedBox(height: 14),
                    Text(
                      'Welcome $name',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (partnerId != null && partnerEmail.isNotEmpty)
                      Text(
                        'Connected with $partnerEmail',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 14,
                        ),
                      ),
                    const SizedBox(height: 18),

                    // ── Pairing UI (shown when no partner) ────────────
                    if (partnerId == null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        child: GlassCard(
                          borderRadius: 30,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Connect With Your Partner',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: partnerEmailController,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Partner Email',
                                ),
                              ),
                              const SizedBox(height: 12),
                              InkWell(
                                borderRadius: BorderRadius.circular(30),
                                onTap: _isPairingLoading
                                    ? null
                                    : () async {
                                        setState(
                                            () => _isPairingLoading = true);
                                        try {
                                          await coupleService
                                              .sendPairingRequest(
                                            partnerEmail:
                                                partnerEmailController.text,
                                          );
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  'Pairing request sent 💜'),
                                            ),
                                          );
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content: Text(e.toString())),
                                          );
                                        } finally {
                                          if (mounted) {
                                            setState(() =>
                                                _isPairingLoading = false);
                                          }
                                        }
                                      },
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.white.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(30),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.20),
                                        blurRadius: 15,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: _isPairingLoading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child:
                                                CircularProgressIndicator(
                                                    strokeWidth: 2),
                                          )
                                        : const Text(
                                            'Send Pairing Request',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              StreamBuilder<
                                  QuerySnapshot<Map<String, dynamic>>>(
                                stream:
                                    coupleService.incomingPairingRequests(),
                                builder: (context, reqSnap) {
                                  final docs =
                                      reqSnap.data?.docs ?? const [];
                                  if (docs.isEmpty) {
                                    return const SizedBox.shrink();
                                  }

                                  final req = docs.first;
                                  final reqData = req.data();
                                  final fromUid =
                                      (reqData['fromUid'] ?? '').toString();
                                  final fromEmail =
                                      (reqData['fromEmail'] ?? '')
                                          .toString();

                                  return Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Pair request from $fromEmail',
                                          style: const TextStyle(
                                              color: Colors.white),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      InkWell(
                                        borderRadius:
                                            BorderRadius.circular(30),
                                        onTap: () async {
                                          try {
                                            await coupleService
                                                .acceptPairingRequest(
                                              requestId: req.id,
                                              partnerUid: fromUid,
                                              partnerEmail: fromEmail,
                                            );

                                            await AlarmService
                                                .requestPermissionsOnceAfterPairingAccepted();
                                            widget.onCoupleIdChanged();
                                          } catch (e) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                  content:
                                                      Text(e.toString())),
                                            );
                                          }
                                        },
                                        child: Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                            vertical: 10,
                                            horizontal: 14,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.25),
                                            borderRadius:
                                                BorderRadius.circular(30),
                                          ),
                                          child: const Text(
                                            'Accept',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox.shrink(),
                    ],

                    const SizedBox(height: 30),

                    // ── Wake Your Partner button ─────────────────────
                    _premiumButton('Wake Your Partner 🔔', Icons.notifications,
                        () async {
                      if (!mounted) return;
                      if (widget.coupleId.isEmpty) return;

                      // Record the wake attempt in relationship stats.
                      final uid =
                          FirebaseAuth.instance.currentUser?.uid ?? '';
                      if (uid.isNotEmpty) {
                        WakeStatsService.recordWakeAttempt(
                          coupleId: widget.coupleId,
                          triggeredByUid: uid,
                        ).catchError((_) {});
                      }

                      final pickedTime = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );

                      if (pickedTime == null) return;

                      final now = DateTime.now();
                      final scheduledDateTime = DateTime(
                        now.year,
                        now.month,
                        now.day,
                        pickedTime.hour,
                        pickedTime.minute,
                      );

                      final currentUid =
                          FirebaseAuth.instance.currentUser?.uid ?? '';
                      if (currentUid.isEmpty) return;

                      final coupleDoc = await FirebaseFirestore.instance
                          .collection('couples')
                          .doc(widget.coupleId)
                          .get();

                      final members = List<String>.from(
                          coupleDoc.data()?['memberUids'] ?? []);
                      if (members.isEmpty) return;

                      final partnerUid = members.firstWhere(
                          (id) => id != currentUid,
                          orElse: () => '');
                      if (partnerUid.isEmpty) return;

                      if (isCollegeTime()) {
                        // College hours: create a wake request (needs approval).
                        await FirebaseFirestore.instance
                            .collection('wake_requests')
                            .add({
                          'createdBy': currentUid,
                          'target': partnerUid,
                          'scheduledTime':
                              Timestamp.fromDate(scheduledDateTime),
                          'status': 'pending',
                          'createdAt': Timestamp.now(),
                        });

                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Wake request sent for approval 💌'),
                          ),
                        );
                      } else {
                        // Outside college hours: directly set alarm on
                        // partner phone via Firestore alarm listener.
                        final alarmId =
                            DateTime.now().millisecondsSinceEpoch;

                        await FirebaseFirestore.instance
                            .collection('couples')
                            .doc(widget.coupleId)
                            .update({
                          'alarm': {
                            'id': alarmId,
                            'createdBy': currentUid,
                            'target': partnerUid,
                            'time': Timestamp.fromDate(scheduledDateTime),
                            'status': 'scheduled',
                            'timestamp': Timestamp.now(),
                          }
                        });

                        await FirebaseFirestore.instance
                            .collection('notifications')
                            .add({
                          'target': partnerUid,
                          'message':
                              'Your partner fixed alarm for ${formatTime(scheduledDateTime)} ⏰',
                          'createdAt': Timestamp.now(),
                        });

                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Alarm set on partner\'s phone for ${formatTime(scheduledDateTime)} ⏰'),
                          ),
                        );
                      }
                    }),

                    if ((FirebaseAuth.instance.currentUser?.uid ?? '')
                        .isNotEmpty)
                      _homeNotificationsCard(
                          FirebaseAuth.instance.currentUser!.uid),

                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            _floatingHearts(),
            Container(
              padding: const EdgeInsets.only(bottom: 10),
              child: const Icon(
                Icons.favorite,
                color: Colors.white70,
                size: 40,
              ),
            )
                .animate(
                    onPlay: (controller) =>
                        controller.repeat(reverse: true))
                .scale(
                  duration: 1500.ms,
                  begin: const Offset(1, 1),
                  end: const Offset(1.2, 1.2),
                )
                .fadeIn(duration: 800.ms),
          ],
        );
      },
    );
  }
}
