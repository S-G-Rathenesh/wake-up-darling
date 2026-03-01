import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../services/wake_stats_service.dart';

/// Stats sub-tab inside the Couple Dashboard.
/// Displays relationship wake stats with real-time Firestore listener:
///   - Total Attempts
///   - Current Streak
///   - Longest Streak
///   - Alarm Status (animated green glow if active)
///   - Clear Logs button
class CoupleStats extends StatelessWidget {
  final String coupleId;

  const CoupleStats({super.key, required this.coupleId});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          _buildAlarmStatusCard(),
          const SizedBox(height: 16),
          _buildPartnerAlarmStatusCard(),
          const SizedBox(height: 16),
          _buildStatsCard(context),
          const SizedBox(height: 16),
          _buildStreakCard(),
        ],
      ),
    );
  }

  // ─── Alarm Status Card ──────────────────────────────────────────────────

  Widget _buildAlarmStatusCard() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: WakeStatsService.streamStats(coupleId),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};

        // Read from alarm.status (live), then top-level alarmStatus, then
        // stats.lastWakeStatus as fallback.
        final alarm = (data['alarm'] as Map<String, dynamic>?) ?? {};
        final liveStatus = (alarm['status'] ?? '').toString();
        final topLevelStatus = (data['alarmStatus'] ?? '').toString();
        final stats = (data['stats'] as Map<String, dynamic>?) ?? {};
        final lastStatus = (stats['lastWakeStatus'] ?? '').toString();

        final effectiveStatus = liveStatus.isNotEmpty
            ? liveStatus
            : topLevelStatus.isNotEmpty
                ? topLevelStatus
                : lastStatus;

        final isActive = _isActiveStatus(effectiveStatus);
        final statusLabel = _getStatusLabel(effectiveStatus);
        final statusColor = _getStatusColor(effectiveStatus);

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: Container(
            key: ValueKey('alarm-$effectiveStatus'),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isActive
                    ? [
                        const Color(0xFF00C853).withValues(alpha: 0.25),
                        const Color(0xFF69F0AE).withValues(alpha: 0.12),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.08),
                        Colors.white.withValues(alpha: 0.04),
                      ],
              ),
              border: Border.all(
                color: isActive
                    ? const Color(0xFF69F0AE).withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.15),
                width: 1.5,
              ),
              boxShadow: [
                if (isActive)
                  BoxShadow(
                    color: const Color(0xFF69F0AE).withValues(alpha: 0.2),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Row(
              children: [
                // Animated indicator dot
                _buildIndicatorDot(isActive, statusColor),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Alarm Status',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isActive
                      ? Icons.notifications_active
                      : Icons.notifications_off_outlined,
                  color: statusColor,
                  size: 28,
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms)
              .slideY(begin: 0.06, end: 0),
        );
      },
    );
  }

  Widget _buildIndicatorDot(bool isActive, Color color) {
    final dot = Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
    );

    if (isActive) {
      return dot
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .fadeIn(begin: 0.5, duration: 800.ms)
          .scaleXY(begin: 1.0, end: 1.3, duration: 800.ms);
    }
    return dot;
  }

  // ─── Partner Alarm Status Card ──────────────────────────────────────────

  Widget _buildPartnerAlarmStatusCard() {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('couples')
          .doc(coupleId)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};

        // Read per-user alarm statuses.
        final alarmStatuses =
            (data['alarmStatuses'] as Map<String, dynamic>?) ?? {};
        final memberUids =
            List<String>.from(data['memberUids'] ?? []);
        final partnerUid = memberUids
            .where((uid) => uid != myUid)
            .firstOrNull ?? '';

        final myStatus =
            (alarmStatuses[myUid] as Map<String, dynamic>?) ?? {};
        final partnerStatus =
            (alarmStatuses[partnerUid] as Map<String, dynamic>?) ?? {};

        final myAlarmActive = myStatus['active'] == true;
        final partnerAlarmActive = partnerStatus['active'] == true;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 12,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.people_outline,
                      color: Colors.white70, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    '💑 Couple Alarm Status',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Your Alarm row
              _alarmStatusRow(
                label: 'Your Alarm',
                isActive: myAlarmActive,
              ),
              const SizedBox(height: 12),
              Divider(
                color: Colors.white.withValues(alpha: 0.10),
                height: 1,
              ),
              const SizedBox(height: 12),

              // Partner Alarm row
              _alarmStatusRow(
                label: 'Partner Alarm',
                isActive: partnerAlarmActive,
              ),
            ],
          ),
        )
            .animate()
            .fadeIn(duration: 500.ms, delay: 50.ms)
            .slideY(begin: 0.06, end: 0);
      },
    );
  }

  Widget _alarmStatusRow({
    required String label,
    required bool isActive,
  }) {
    final color = isActive ? const Color(0xFF69F0AE) : Colors.white54;
    final statusText = isActive ? 'Active' : 'Inactive';

    return Row(
      children: [
        _buildIndicatorDot(isActive, color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          statusText,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // ─── Stats Card (Total Attempts) ────────────────────────────────────────

  Widget _buildStatsCard(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: WakeStatsService.streamStats(coupleId),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final stats = (data['stats'] as Map<String, dynamic>?) ?? {};

        // Support both nested stats.* and top-level fields
        final total = (stats['totalWakeAttempts'] ??
            data['totalAttempts'] ??
            0) as int;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: Container(
            key: ValueKey('stats-$total'),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(24),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.18)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Title + Clear button ─────────────────────────
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
                    _buildClearButton(context),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Big total attempts number ────────────────────
                Center(
                  child: Column(
                    children: [
                      Text(
                        '$total',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Total Wake Attempts',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 100.ms)
              .slideY(begin: 0.06, end: 0),
        );
      },
    );
  }

  Widget _buildClearButton(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF2A1B3D),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'Clear Relationship Stats?',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'This will reset all wake attempts and streaks '
              'to zero. Alarm status will not be changed.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear',
                    style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await WakeStatsService.clearWakeLogs(coupleId: coupleId);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: Colors.redAccent.withValues(alpha: 0.30)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: Colors.redAccent, size: 14),
            SizedBox(width: 4),
            Text(
              'Clear',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Streak Card ────────────────────────────────────────────────────────

  Widget _buildStreakCard() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: WakeStatsService.streamStats(coupleId),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final stats = (data['stats'] as Map<String, dynamic>?) ?? {};

        final currentStreak =
            (stats['currentStreak'] ?? data['currentStreak'] ?? 0) as int;
        final longestStreak =
            (stats['longestStreak'] ?? data['longestStreak'] ?? 0) as int;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: Container(
            key: ValueKey('streak-$currentStreak-$longestStreak'),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(24),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.18)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // ── Current Streak ───────────────────────────────
                _streakRow(
                  icon: Icons.local_fire_department,
                  iconColor: const Color(0xFFFF6B6B),
                  label: 'Current Streak',
                  value: currentStreak,
                  emoji: '🔥',
                ),
                const SizedBox(height: 16),
                Divider(
                  color: Colors.white.withValues(alpha: 0.10),
                  height: 1,
                ),
                const SizedBox(height: 16),
                // ── Longest Streak ───────────────────────────────
                _streakRow(
                  icon: Icons.emoji_events,
                  iconColor: const Color(0xFFFFD700),
                  label: 'Longest Streak',
                  value: longestStreak,
                  emoji: '🏆',
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 200.ms)
              .slideY(begin: 0.06, end: 0),
        );
      },
    );
  }

  Widget _streakRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required int value,
    required String emoji,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$emoji $label',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$value day${value == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  bool _isActiveStatus(String status) {
    return [
      'active',
      'pending',
      'triggered',
      'ringing',
      'Active',
    ].contains(status);
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'active':
      case 'pending':
      case 'triggered':
        return '🟢 Active';
      case 'ringing':
        return '🔔 Ringing!';
      case 'completed':
      case 'woke':
        return '✅ Partner Woke Up';
      case 'cancelled':
        return '⏹️ Cancelled';
      case 'ignored':
        return '❌ Ignored';
      default:
        return '⚫ Inactive';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
      case 'pending':
      case 'triggered':
      case 'ringing':
      case 'completed':
      case 'woke':
        return const Color(0xFF69F0AE);
      case 'cancelled':
        return Colors.orangeAccent;
      case 'ignored':
        return const Color(0xFFFF6B6B);
      default:
        return Colors.white54;
    }
  }
}
