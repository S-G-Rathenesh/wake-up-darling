import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../widgets/romantic_hearts_overlay.dart';

import '../services/alarm_service.dart';
import '../services/user_service.dart';
import '../services/wake_stats_service.dart';
import 'chat_screen_v2.dart';

class PartnerDashboardScreen extends StatefulWidget {
  const PartnerDashboardScreen({super.key});

  @override
  State<PartnerDashboardScreen> createState() => _PartnerDashboardScreenState();
}

class _PartnerDashboardScreenState extends State<PartnerDashboardScreen> {
  final UserService userService = UserService();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => userService.ensureUserProfileExists());
  }

  // ──────────────────────────────────────────────────────────────────
  // Relationship Stats Card
  // ──────────────────────────────────────────────────────────────────
  Widget _buildStatsCard(BuildContext context, String coupleId) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: WakeStatsService.streamStats(coupleId),
      builder: (context, snap) {
        final data = snap.data?.data() ?? <String, dynamic>{};
        final stats = (data['stats'] as Map<String, dynamic>?) ?? {};

        final total = (stats['totalWakeAttempts'] ?? 0) as int;
        final streak = (stats['currentStreak'] ?? 0) as int;
        final best = (stats['longestStreak'] ?? 0) as int;
        final lastStatus = (stats['lastWakeStatus'] ?? '').toString();

        // ── Alarm status label + color ─────────────────────────────────
        late Color statusColor;
        late String statusLabel;
        late bool isRinging;

        switch (lastStatus) {
          case 'ringing':
            statusColor = const Color(0xFF69F0AE);
            statusLabel = 'Ringing';
            isRinging = true;
            break;
          case 'woke':
            statusColor = const Color(0xFF69F0AE);
            statusLabel = '✅ Partner Woke Up';
            isRinging = false;
            break;
          case 'ignored':
            statusColor = const Color(0xFFFF6B6B);
            statusLabel = '❌ Ignored';
            isRinging = false;
            break;
          default:
            statusColor = Colors.white54;
            statusLabel = 'N/A';
            isRinging = false;
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: Container(
            key: ValueKey('$total-$streak-$best-$lastStatus'),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(28),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Title + Clear button ───────────────────────────
                Row(
                  children: [
                    const Icon(Icons.bar_chart_rounded,
                        color: Colors.white70, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      '📊 Relationship Stats',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Clear Wake Logs'),
                            content: const Text(
                                'Delete all wake logs and reset all stats?'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, true),
                                child: const Text('Clear',
                                    style: TextStyle(
                                        color: Colors.redAccent)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await WakeStatsService.clearWakeLogs(
                              coupleId: coupleId);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color:
                                  Colors.white.withValues(alpha: 0.20)),
                        ),
                        child: const Text(
                          'Clear Logs',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // ── Stat rows ────────────────────────────────────
                _statRow(Icons.notifications_active, '🔔 Total Attempts',
                    '$total'),
                const SizedBox(height: 10),
                _statRow(Icons.local_fire_department, '🔥 Current Streak',
                    '$streak day${streak == 1 ? '' : 's'}'),
                const SizedBox(height: 10),
                _statRow(Icons.emoji_events, '🏆 Longest Streak',
                    '$best day${best == 1 ? '' : 's'}'),
                const SizedBox(height: 14),
                // ── Alarm status ─────────────────────────────────────
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: statusColor.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Animated dot
                      if (isRinging)
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        )
                            .animate(onPlay: (c) => c.repeat(reverse: true))
                            .scaleXY(begin: 1.0, end: 1.5, duration: 600.ms)
                            .fadeIn()
                      else
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      const SizedBox(width: 8),
                      Text(
                        '🔔 Current Alarm Status:  $statusLabel',
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.06, end: 0),
        );
      },
    );
  }

  Widget _statRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75), fontSize: 13),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Partner 💜',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: userService.getCurrentUserProfile(),
                  builder: (context, snapshot) {
                    Widget loading() {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Could not load couple info',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                InkWell(
                                  borderRadius: BorderRadius.circular(30),
                                  onTap: () async {
                                    await userService.ensureUserProfileExists();
                                    if (mounted) setState(() {});
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                      horizontal: 18,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.18),
                                      ),
                                    ),
                                    child: const Text(
                                      'Retry',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    // 1) Loading state: wait for Firestore to finish initial fetch.
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: loading(),
                      );
                    }

                    // 2) No profile doc (or not logged in -> empty stream)
                    if (!snapshot.hasData || !(snapshot.data?.exists ?? false)) {
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Center(
                          key: const ValueKey('profile-missing'),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Profile not found',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(30),
                                    onTap: () async {
                                      await userService.ensureUserProfileExists();
                                      if (mounted) setState(() {});
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                        horizontal: 18,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(30),
                                        border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.18),
                                        ),
                                      ),
                                      child: const Text(
                                        'Create profile',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }

                    final doc = snapshot.data!;
                    final data = doc.data();
                    if (data == null) {
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: loading(),
                      );
                    }

                    final partnerId = (data['partnerId'] ?? '').toString().trim();
                    final partnerEmail = (data['partnerEmail'] ?? '').toString().trim();
                    final coupleId = (data['coupleId'] ?? '').toString().trim();

                    // 3) No partner state
                    if (partnerId.isEmpty) {
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Center(
                          key: const ValueKey('no-partner'),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.favorite_border,
                                color: Colors.white.withValues(alpha: 0.7),
                                size: 80,
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'No partner connected 💔',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    // 4) Connected state
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        key: const ValueKey('connected'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Partner Info Card ─────────────────────────────
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Couple Dashboard 💕',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  partnerEmail.isEmpty
                                      ? 'Partner connected 💜'
                                      : 'Partner: $partnerEmail',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (coupleId.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Couple ID: $coupleId',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.85),
                                    ),
                                  ),
                                ],

                                // ── Remote Alarm Cancel (creator only) ──────
                                if (coupleId.isNotEmpty)
                                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                                    stream:
                                        AlarmService.streamCoupleDoc(coupleId),
                                    builder: (context, alarmSnap) {
                                      final alarmData = alarmSnap
                                          .data
                                          ?.data();
                                      final alarm = alarmData?['alarm']
                                          as Map<String, dynamic>?;

                                      if (alarm == null) {
                                        return const SizedBox.shrink();
                                      }

                                      final status =
                                          (alarm['status'] ?? '').toString();
                                      final createdBy =
                                          (alarm['createdBy'] ?? '').toString();
                                        final myUid = FirebaseAuth
                                            .instance.currentUser?.uid ??
                                          '';

                                      // Show only for the alarm creator AND
                                      // only while the alarm is active.
                                      final isActiveAlarm = status ==
                                              'scheduled' ||
                                          status == 'ringing';
                                      final isCreator = createdBy.isNotEmpty &&
                                          createdBy == myUid;

                                      if (!isActiveAlarm || !isCreator) {
                                        return const SizedBox.shrink();
                                      }

                                      final alarmId =
                                          (alarm['id'] as int?) ?? 0;

                                      return Padding(
                                        padding: const EdgeInsets.only(top: 14),
                                        child: InkWell(
                                          borderRadius:
                                              BorderRadius.circular(30),
                                          onTap: () async {
                                            // 1. Update Firestore status.
                                            await AlarmService
                                                .updateCoupleAlarmStatus(
                                              coupleId: coupleId,
                                              status: 'cancelled',
                                            );
                                            // 2. Cancel notification locally.
                                            await AlarmService
                                                .cancelAlarm(alarmId);
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 14),
                                            decoration: BoxDecoration(
                                              color: Colors.red
                                                  .withValues(alpha: 0.55),
                                              borderRadius:
                                                  BorderRadius.circular(30),
                                              border: Border.all(
                                                color: Colors.red
                                                    .withValues(alpha: 0.70),
                                              ),
                                            ),
                                            child: const Center(
                                              child: Text(
                                                'Disable Alarm 🔕',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ── Chat with Partner ─────────────────────────
                          InkWell(
                            borderRadius: BorderRadius.circular(30),
                            onTap: () {
                              Navigator.push(
                                context,
                                PageRouteBuilder(
                                  pageBuilder: (_, __, ___) => ChatScreenV2(
                                    coupleId: coupleId,
                                    partnerId: partnerId,
                                    partnerName: partnerEmail.isNotEmpty
                                        ? partnerEmail.split('@').first
                                        : 'Partner',
                                  ),
                                  transitionsBuilder:
                                      (_, anim, __, child) =>
                                          FadeTransition(
                                              opacity: anim, child: child),
                                  transitionDuration:
                                      const Duration(milliseconds: 300),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFE040FB),
                                    Color(0xFF7C4DFF),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFE040FB)
                                        .withValues(alpha: 0.35),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.chat_rounded,
                                      color: Colors.white, size: 22),
                                  SizedBox(width: 10),
                                  Text(
                                    'Chat with Partner 💬',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),
                          // ── Relationship Stats Card ────────────────────
                          _buildStatsCard(context, coupleId),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      const RomanticHeartsOverlay(),
    ],
  ),
);
  }
}
