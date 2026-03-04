import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:android_intent_plus/android_intent.dart';

import '../services/alarm_service.dart';
import '../services/call_limit_service.dart';
import '../widgets/romantic_hearts_overlay.dart';
import 'about_screen.dart';
import 'login_screen.dart';

class AppSettingsScreen extends StatefulWidget {
  final String coupleId;

  const AppSettingsScreen({super.key, required this.coupleId});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  static const _gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0), Color(0xFF6A11CB)],
  );

  late String _coupleId;
  bool _loadingCoupleId = false;

  @override
  void initState() {
    super.initState();
    _coupleId = widget.coupleId;
    // If the parent didn't pass a coupleId yet, fetch it ourselves.
    if (_coupleId.isEmpty) _fetchCoupleId();
  }

  Future<void> _fetchCoupleId() async {
    if (_loadingCoupleId) return;
    setState(() => _loadingCoupleId = true);
    try {
      final id = await AlarmService.fetchCurrentUserCoupleId();
      if (mounted) setState(() => _coupleId = id);
    } finally {
      if (mounted) setState(() => _loadingCoupleId = false);
    }
  }

  void _showAnimatedDialog(BuildContext context, Widget dialog) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, animation, secondaryAnimation) => dialog,
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) =>
          ScaleTransition(
        scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        child: child,
      ),
    );
  }

  Widget _themedDialog({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String content,
    required List<Widget> actions,
  }) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: _gradient,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 40),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              content,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 24),
            Row(children: actions),
          ],
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Color titleColor,
    String? subtitle,
    FontWeight fontWeight = FontWeight.normal,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: titleColor,
                          fontSize: 16,
                          fontWeight: fontWeight)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }

  String _fmtHm(int hour, int minute) {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _partnerAlarmSyncTile() {
    if (_coupleId.isEmpty) {
      return _tile(
        icon: Icons.sync,
        iconColor: Colors.white,
        title: 'Partner Alarm Sync',
        titleColor: Colors.white,
        subtitle: _loadingCoupleId
            ? 'Fetching couple…'
            : 'Pair with a partner to sync alarms',
        onTap: () async {
          if (_coupleId.isEmpty) await _fetchCoupleId();
        },
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('couples')
          .doc(_coupleId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? <String, dynamic>{};
        final remote = data['remoteAlarm'] as Map<String, dynamic>?;

        final status = (remote?['status'] ?? 'none').toString();
        final hour = (remote?['hour'] as int?) ?? -1;
        final minute = (remote?['minute'] as int?) ?? -1;

        final timePart = (hour >= 0 && minute >= 0)
            ? ' • ${_fmtHm(hour, minute)}'
            : '';

        final subtitle = remote == null
            ? 'No remote alarm sent yet'
            : 'Status: $status$timePart';

        return _tile(
          icon: Icons.sync,
          iconColor: Colors.white,
          title: 'Partner Alarm Sync',
          titleColor: Colors.white,
          subtitle: subtitle,
          onTap: () {
            final error = (remote?['error'] ?? '').toString();
            _showAnimatedDialog(
              context,
              _themedDialog(
                context: context,
                icon: Icons.sync,
                iconColor: Colors.white,
                title: 'Partner Alarm Sync',
                content: remote == null
                    ? 'No remote alarm request found.\n\nUse “Wake Your Partner” on the Dashboard to send one.'
                    : 'Status: $status\n'
                        'Time: ${(hour >= 0 && minute >= 0) ? _fmtHm(hour, minute) : '—'}\n'
                        '${error.isNotEmpty ? '\nError: $error\n' : ''}'
                        '\nIf status is completed, the partner phone applied the alarm.',
                actions: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close',
                          style: TextStyle(color: Colors.white70)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.20),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15)),
                      ),
                      onPressed: remote == null || hour < 0 || minute < 0
                          ? null
                          : () async {
                              final uid =
                                  FirebaseAuth.instance.currentUser?.uid ?? '';
                              if (uid.isEmpty) return;
                              final requestId =
                                  DateTime.now().millisecondsSinceEpoch;

                              await FirebaseFirestore.instance
                                  .collection('couples')
                                  .doc(_coupleId)
                                  .set({
                                'remoteAlarm': {
                                  'requestId': requestId,
                                  'status': 'pending',
                                  'hour': hour,
                                  'minute': minute,
                                  'createdBy': uid,
                                  'createdAt': Timestamp.now(),
                                }
                              }, SetOptions(merge: true));

                              if (!context.mounted) return;
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Resent to partner phone. Waiting for completion…')),
                              );
                            },
                      child: const Text('Resend',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Settings',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: _gradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                const SizedBox(height: 12),

                // ── Unpair Partner ───────────────────────────────────────────
                _tile(
                  icon: Icons.link_off,
                  iconColor: Colors.redAccent,
                  title: 'Unpair Partner',
                  titleColor: Colors.redAccent,
                  onTap: () {
                    _showAnimatedDialog(
                      context,
                      _themedDialog(
                        context: context,
                        icon: Icons.link_off,
                        iconColor: Colors.redAccent,
                        title: 'Request Unpair',
                        content: 'Send unpair request to partner?',
                        actions: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel',
                                  style: TextStyle(color: Colors.white70)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.20),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15)),
                              ),
                              onPressed: () async {
                                final uid = FirebaseAuth
                                        .instance.currentUser?.uid ??
                                    '';
                                if (_coupleId.isNotEmpty && uid.isNotEmpty) {
                                  await FirebaseFirestore.instance
                                      .collection('couples')
                                      .doc(_coupleId)
                                      .update({'unpairRequest': uid});
                                }
                                if (!context.mounted) return;
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Unpair request sent to partner 💔')),
                                );
                              },
                              child: const Text('Send',
                                  style: TextStyle(color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 10),

                // ── Emergency Wake ───────────────────────────────────────────
                _tile(
                  icon: Icons.warning_amber_rounded,
                  iconColor: Colors.redAccent,
                  title: 'Emergency Wake',
                  titleColor: Colors.redAccent,
                  subtitle: 'Sends high-priority FCM → rings alarm even in silent/DND',
                  fontWeight: FontWeight.bold,
                  onTap: () {
                    _showAnimatedDialog(
                      context,
                      _themedDialog(
                        context: context,
                        icon: Icons.warning_amber_rounded,
                        iconColor: Colors.redAccent,
                        title: 'Confirm Emergency Wake',
                        content:
                            'This will open Google Clock and set alarm immediately.\n\nAre you sure?',
                        actions: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel',
                                  style: TextStyle(color: Colors.white70)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15)),
                              ),
                              onPressed: () async {
                                Navigator.pop(context);
                                if (_coupleId.isEmpty) await _fetchCoupleId();
                                if (_coupleId.isEmpty) return;
                                final currentUid = FirebaseAuth
                                        .instance.currentUser?.uid ??
                                    '';
                                if (currentUid.isEmpty) return;

                                // Fetch partner uid from couple doc.
                                final coupleDoc = await FirebaseFirestore
                                    .instance
                                    .collection('couples')
                                    .doc(_coupleId)
                                    .get();
                                final membersList =
                                    List<String>.from(
                                        coupleDoc.data()?['memberUids'] ?? []);
                                final partnerUid = membersList
                                    .firstWhere(
                                        (id) => id != currentUid,
                                        orElse: () => '');
                                if (partnerUid.isEmpty) return;

                                // College hours (8 AM – 5:30 PM): send request instead.
                                final now = DateTime.now();
                                final collegeStart = DateTime(now.year, now.month, now.day, 8, 0);
                                final collegeEnd = DateTime(now.year, now.month, now.day, 17, 30);
                                final isCollege = now.isAfter(collegeStart) && now.isBefore(collegeEnd);

                                if (isCollege) {
                                  await FirebaseFirestore.instance
                                      .collection('wake_requests')
                                      .add({
                                    'createdBy': currentUid,
                                    'target': partnerUid,
                                    'scheduledTime': Timestamp.now(),
                                    'status': 'pending',
                                    'type': 'emergency',
                                    'createdAt': Timestamp.now(),
                                  });

                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          '🚨 College hours — emergency request sent for approval 💌'),
                                      backgroundColor: Colors.orangeAccent,
                                    ),
                                  );
                                  return;
                                }

                                await FirebaseFirestore.instance
                                    .collection('couples')
                                    .doc(_coupleId)
                                    .update({
                                  'alarm': {
                                    'id': DateTime.now()
                                        .millisecondsSinceEpoch,
                                    'createdBy': currentUid,
                                    'target': partnerUid,
                                    'status': 'emergency',
                                    'timestamp': Timestamp.now(),
                                  }
                                });

                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        '🚨 Emergency sent! Partner\'s alarm will ring shortly.'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              },
                              child: const Text('Yes, Wake Now'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 10),

                // ── Partner Alarm Sync Status ───────────────────────────────
                _partnerAlarmSyncTile(),

                const SizedBox(height: 10),

                // ── Daily Call Limits ──────────────────────────────────────
                _tile(
                  icon: Icons.timer,
                  iconColor: Colors.cyanAccent,
                  title: 'Daily Call Limits',
                  titleColor: Colors.white,
                  subtitle:
                      'Voice: ${CallLimitService.maxVoiceMinutesPerDay} min • Video: ${CallLimitService.maxVideoMinutesPerDay} min',
                  onTap: () {
                    _showAnimatedDialog(
                      context,
                      _themedDialog(
                        context: context,
                        icon: Icons.timer,
                        iconColor: Colors.cyanAccent,
                        title: 'Daily Call Limits',
                        content:
                            'To stay within the free tier, daily limits apply per couple:\n\n'
                            '📞 Voice calls — ${CallLimitService.maxVoiceMinutesPerDay} min/day\n'
                            '📹 Video calls — ${CallLimitService.maxVideoMinutesPerDay} min/day\n\n'
                            'Limits reset automatically at midnight.',
                        actions: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purpleAccent,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Got it',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 13)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 10),

                // ── Voice Call Limit Info ──────────────────────────────────
                _tile(
                  icon: Icons.phone_in_talk,
                  iconColor: Colors.greenAccent,
                  title: 'Voice Call Limit',
                  titleColor: Colors.white,
                  subtitle: '30 min/day',
                  onTap: () {
                    _showAnimatedDialog(
                      context,
                      _themedDialog(
                        context: context,
                        icon: Icons.phone_in_talk,
                        iconColor: Colors.greenAccent,
                        title: 'Voice Call Limit',
                        content:
                            'You have 30 minutes of voice calling each day.\n\n'
                            'The timer resets at midnight.',
                        actions: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('OK',
                                  style:
                                      TextStyle(color: Colors.purpleAccent)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 10),

                // ── Battery Optimization ─────────────────────────────────────
                _tile(
                  icon: Icons.battery_alert,
                  iconColor: Colors.orangeAccent,
                  title: 'Fix Battery Optimization',
                  titleColor: Colors.white,
                  subtitle:
                      'Required so alarms ring even when screen is off. Tap → find this app → Unrestricted.',
                  onTap: () async {
                    try {
                      await const AndroidIntent(
                        action:
                            'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
                      ).launch();
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not open battery settings'),
                        ),
                      );
                    }
                  },
                ),

                const SizedBox(height: 10),

                // ── About ───────────────────────────────────────────────────
                _tile(
                  icon: Icons.info_outline,
                  iconColor: Colors.lightBlueAccent,
                  title: 'About',
                  titleColor: Colors.white,
                  subtitle: 'App info, version, privacy',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AboutScreen()),
                    );
                  },
                ),

                const SizedBox(height: 10),

                // ── Logout ──────────────────────────────────────────────────
                _tile(
                  icon: Icons.logout,
                  iconColor: Colors.white,
                  title: 'Logout',
                  titleColor: Colors.white,
                  onTap: () async {
                    await FirebaseAuth.instance.signOut();
                    if (!context.mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (_) => false,
                    );
                  },
                ),
              ],
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
