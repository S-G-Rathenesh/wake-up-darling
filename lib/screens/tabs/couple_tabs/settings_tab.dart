import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../services/alarm_service.dart';
import '../../login_screen.dart';

/// Settings sub-tab inside the Couple Dashboard.
/// Provides Unpair, Emergency Wake, Partner Alarm Sync, Battery Optimization,
/// and Logout — mirrors AppSettingsScreen but embedded as a tab.
class CoupleSettings extends StatefulWidget {
  final String coupleId;
  const CoupleSettings({super.key, required this.coupleId});

  @override
  State<CoupleSettings> createState() => _CoupleSettingsState();
}

class _CoupleSettingsState extends State<CoupleSettings> {
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
    if (_coupleId.isEmpty) _fetchCoupleId();
  }

  @override
  void didUpdateWidget(covariant CoupleSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coupleId != widget.coupleId) {
      _coupleId = widget.coupleId;
    }
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
      transitionBuilder:
          (dialogContext, animation, secondaryAnimation, child) =>
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
    ).animate().fadeIn(duration: 300.ms).slideX(begin: 0.03, end: 0);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          // ── Unpair Partner ──────────────────────────────────────
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
                          final uid =
                              FirebaseAuth.instance.currentUser?.uid ?? '';
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

          // ── Emergency Wake ─────────────────────────────────────
          _tile(
            icon: Icons.warning_amber_rounded,
            iconColor: Colors.redAccent,
            title: 'Emergency Wake',
            titleColor: Colors.redAccent,
            subtitle:
                'Sends high-priority FCM → rings alarm even in silent/DND',
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
                      'This will ring alarm on partner\'s phone immediately.\n\nAre you sure?',
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
                          final currentUid =
                              FirebaseAuth.instance.currentUser?.uid ?? '';
                          if (currentUid.isEmpty) return;

                          final coupleDoc = await FirebaseFirestore.instance
                              .collection('couples')
                              .doc(_coupleId)
                              .get();
                          final membersList = List<String>.from(
                              coupleDoc.data()?['memberUids'] ?? []);
                          final partnerUid = membersList.firstWhere(
                              (id) => id != currentUid,
                              orElse: () => '');
                          if (partnerUid.isEmpty) return;

                          // College hours (8 AM – 5:30 PM): send request.
                          final now = DateTime.now();
                          final collegeStart = DateTime(
                              now.year, now.month, now.day, 8, 0);
                          final collegeEnd = DateTime(
                              now.year, now.month, now.day, 17, 30);
                          final isCollege = now.isAfter(collegeStart) &&
                              now.isBefore(collegeEnd);

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
                              'id': DateTime.now().millisecondsSinceEpoch,
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

          // ── Battery Optimization ────────────────────────────────
          _tile(
            icon: Icons.battery_alert,
            iconColor: Colors.orangeAccent,
            title: 'Fix Battery Optimization',
            titleColor: Colors.white,
            subtitle:
                'Required so alarms ring even when screen is off.',
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

          // ── Couple ID ──────────────────────────────────────────
          if (_coupleId.isNotEmpty)
            _tile(
              icon: Icons.info_outline,
              iconColor: Colors.white54,
              title: 'Couple ID',
              titleColor: Colors.white70,
              subtitle: _coupleId,
              onTap: () {},
            ),
          const SizedBox(height: 10),

          // ── Logout ─────────────────────────────────────────────
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
    );
  }
}
