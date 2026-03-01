import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'services/auth_service.dart';
import 'services/call_repository.dart';
import 'screens/profile_screen.dart';
import 'screens/app_settings_screen.dart';
import 'screens/incoming_call_screen.dart';
import 'services/user_service.dart';
import 'services/couple_service.dart';
import 'services/alarm_service.dart';
import 'services/alarm_listener_service.dart';

import 'widgets/animated_gradient_bg.dart';
import 'widgets/animated_bottom_nav.dart';
import 'widgets/romantic_hearts_overlay.dart';
import 'screens/tabs/wake_tab.dart';
import 'screens/tabs/alerts_tab.dart';
import 'screens/tabs/couple_dashboard_tab.dart';

/// Root scaffold with BottomNavigationBar — 3 tabs:
///   0: Wake  (alarm scheduling, pairing)
///   1: Alerts (incoming wake requests)
///   2: Couple (Relationship Hub — Chat, Calls, Media, Stats, Settings)
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  final auth = AuthService();
  final userService = UserService();
  final coupleService = CoupleService();

  late final AnimationController _controller;
  late final Animation<double> _fade;
  StreamSubscription<DocumentSnapshot>? _coupleAlarmSub;
  StreamSubscription? _incomingCallSub;
  StreamSubscription? _alertsBadgeSub;
  StreamSubscription? _messagesBadgeSub;
  StreamSubscription? _notificationsBadgeSub;
  final _callRepo = CallRepository();
  bool _incomingCallScreenOpen = false;
  String _coupleId = '';
  int _currentTab = 0;
  int _alertsBadge = 0;
  int _messageBadge = 0;
  int _wakeBadge = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      coupleService.syncMyCoupleFromAcceptedRequests();
      AlarmListenerService.instance.start();
      _startCoupleUiListener();
    });
  }

  /// Lightweight listener for unpair requests only — alarm scheduling
  /// is handled by the global [AlarmListenerService] singleton which runs
  /// independently of any screen.
  Future<void> _startCoupleUiListener() async {
    final coupleId = await AlarmService.fetchCurrentUserCoupleId();
    if (coupleId.isEmpty) return;

    if (mounted) setState(() => _coupleId = coupleId);

    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // ── Badge listeners ───────────────────────────────────────────
    _startBadgeListeners(coupleId, myUid);

    // ── Incoming call listener ────────────────────────────────────
    _startIncomingCallListener(myUid);

    _coupleAlarmSub?.cancel();
    _coupleAlarmSub = AlarmService.streamCoupleDoc(coupleId).listen(
      (snapshot) async {
        if (!snapshot.exists) return;
        final data = snapshot.data();

        // ── Unpair request handling ───────────────────────────────────
        final unpairReq = (data?['unpairRequest'] ?? '').toString();
        if (unpairReq.isNotEmpty && unpairReq != myUid && mounted) {
          _showUnpairDialog(coupleId, myUid);
          return;
        }
      },
    );
  }

  /// Listens to Firestore for badge counts on each tab.
  void _startBadgeListeners(String coupleId, String myUid) {
    _alertsBadgeSub?.cancel();
    _messagesBadgeSub?.cancel();
    _notificationsBadgeSub?.cancel();

    if (coupleId.isEmpty || myUid.isEmpty) return;

    // Alerts tab: pending wake requests targeting me.
    _alertsBadgeSub = FirebaseFirestore.instance
        .collection('couples')
        .doc(coupleId)
        .collection('wakeRequests')
        .where('receiverId', isEqualTo: myUid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _alertsBadge = snap.docs.length);
    });

    // Couple tab: unread chat messages to me.
    _messagesBadgeSub = FirebaseFirestore.instance
        .collection('Chats')
        .doc(coupleId)
        .collection('Messages')
        .where('receiverId', isEqualTo: myUid)
        .where('readStatus', isNotEqualTo: 'read')
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _messageBadge = snap.docs.length);
    });

    // Wake tab: notifications (e.g. alarm triggers) unread.
    _notificationsBadgeSub = FirebaseFirestore.instance
        .collection('users')
        .doc(myUid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _wakeBadge = snap.docs.length);
    });
  }

  @override
  void dispose() {
    _coupleAlarmSub?.cancel();
    _incomingCallSub?.cancel();
    _alertsBadgeSub?.cancel();
    _messagesBadgeSub?.cancel();
    _notificationsBadgeSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _showUnpairDialog(String coupleId, String myUid) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Unpair Request'),
        content: const Text('Your partner wants to unpair. Accept?'),
        actions: [
          TextButton(
            child: const Text('Decline'),
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('couples')
                  .doc(coupleId)
                  .update({'unpairRequest': FieldValue.delete()});
              if (!mounted) return;
              Navigator.pop(context);
            },
          ),
          TextButton(
            child: const Text('Accept', style: TextStyle(color: Colors.red)),
            onPressed: () async {
              Navigator.pop(context);
              try {
                final coupleSnap = await FirebaseFirestore.instance
                    .collection('couples')
                    .doc(coupleId)
                    .get();
                final coupleData = coupleSnap.data() ?? {};
                final members =
                    (coupleData['memberUids'] as List<dynamic>? ?? [])
                        .map((e) => e.toString())
                        .toList();

                final batch = FirebaseFirestore.instance.batch();
                batch.delete(FirebaseFirestore.instance
                    .collection('couples')
                    .doc(coupleId));
                for (final uid in members) {
                  batch.update(
                      FirebaseFirestore.instance.collection('users').doc(uid), {
                    'partnerId': FieldValue.delete(),
                    'partnerEmail': FieldValue.delete()
                  });
                }
                if (members.isEmpty) {
                  batch.update(
                      FirebaseFirestore.instance
                          .collection('users')
                          .doc(myUid),
                      {
                        'partnerId': FieldValue.delete(),
                        'partnerEmail': FieldValue.delete()
                      });
                }
                await batch.commit();
              } catch (e) {
                debugPrint('[Unpair] error: $e');
              }
            },
          ),
        ],
      ),
    );
  }

  // ── Incoming call listener ─────────────────────────────────────────

  void _startIncomingCallListener(String currentUserId) {
    _incomingCallSub?.cancel();
    if (currentUserId.isEmpty) return;

    _incomingCallSub = _callRepo.listenForIncomingCalls(
      currentUserId: currentUserId,
      onIncomingCall: (call) {
        if (!mounted) return;
        // Prevent opening multiple incoming call screens.
        if (_incomingCallScreenOpen) return;
        _incomingCallScreenOpen = true;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IncomingCallScreen(call: call),
          ),
        ).then((_) {
          _incomingCallScreenOpen = false;
        });
      },
    );
  }

  Future<void> _pushFade(Widget page) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const CircleAvatar(
            backgroundColor: Colors.white24,
            child: Icon(Icons.person, color: Colors.white),
          ),
          onPressed: () => _pushFade(const ProfileScreen()),
        ),
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            _currentTab == 0
                ? 'Wake Up Darling'
                : _currentTab == 1
                    ? 'Alerts'
                    : 'Couple Hub',
            key: ValueKey(_currentTab),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () =>
                _pushFade(AppSettingsScreen(coupleId: _coupleId)),
          ),
        ],
      ),
      body: Stack(
        children: [
          const AnimatedGradientBackground(),
          const RomanticHeartsOverlay(),
          SafeArea(
            bottom: false,
            child: FadeTransition(
              opacity: _fade,
              child: IndexedStack(
                index: _currentTab,
                children: [
                  WakeTab(
                    coupleId: _coupleId,
                    onCoupleIdChanged: () => _startCoupleUiListener(),
                  ),
                  const AlertsTab(),
                  CoupleDashboardTab(coupleId: _coupleId),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AnimatedBottomNav(
        currentIndex: _currentTab,
        onTap: (i) => setState(() => _currentTab = i),
        items: [
          AnimatedNavItem(
            icon: Icons.notifications_active_outlined,
            activeIcon: Icons.notifications_active,
            label: 'Wake',
            badgeCount: _wakeBadge,
          ),
          AnimatedNavItem(
            icon: Icons.mail_outline,
            activeIcon: Icons.mail,
            label: 'Alerts',
            badgeCount: _alertsBadge,
          ),
          AnimatedNavItem(
            icon: Icons.favorite_border,
            activeIcon: Icons.favorite,
            label: 'Couple',
            badgeCount: _messageBadge,
          ),
        ],
      ),
    );
  }
}
