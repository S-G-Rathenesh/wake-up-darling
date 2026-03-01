import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../services/user_service.dart';
import 'couple_tabs/chat_tab.dart';
import 'couple_tabs/calls_tab.dart';
import 'couple_tabs/media_tab.dart';
import 'couple_tabs/stats_tab.dart';

/// The "Couple" tab — Relationship Hub with 4 sub-tabs:
/// Chat, Calls, Media, Stats.
class CoupleDashboardTab extends StatefulWidget {
  final String coupleId;

  const CoupleDashboardTab({super.key, required this.coupleId});

  @override
  State<CoupleDashboardTab> createState() => _CoupleDashboardTabState();
}

class _CoupleDashboardTabState extends State<CoupleDashboardTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final userService = UserService();

  String _partnerId = '';
  String _partnerName = '';
  String _partnerEmail = '';
  bool _loading = true;

  // Badge counts for sub-tabs
  int _unreadChats = 0;
  int _missedCalls = 0;
  StreamSubscription? _chatBadgeSub;
  StreamSubscription? _callBadgeSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadPartnerInfo();
  }

  @override
  void didUpdateWidget(covariant CoupleDashboardTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coupleId != widget.coupleId) {
      _loadPartnerInfo();
    }
  }

  Future<void> _loadPartnerInfo() async {
    if (widget.coupleId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final coupleDoc = await FirebaseFirestore.instance
          .collection('couples')
          .doc(widget.coupleId)
          .get();
      final members =
          List<String>.from(coupleDoc.data()?['memberUids'] ?? []);
      final partnerUid =
          members.firstWhere((id) => id != currentUid, orElse: () => '');

      if (partnerUid.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final partnerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(partnerUid)
          .get();
      final pData = partnerDoc.data() ?? {};
      final pName = (pData['name'] ?? 'Partner').toString();
      final pEmail = (pData['email'] ?? '').toString();

      if (mounted) {
        setState(() {
          _partnerId = partnerUid;
          _partnerName = pName;
          _partnerEmail = pEmail;
          _loading = false;
        });
        _startBadgeListeners(currentUid);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startBadgeListeners(String myUid) {
    _chatBadgeSub?.cancel();
    _callBadgeSub?.cancel();
    if (widget.coupleId.isEmpty || myUid.isEmpty) return;

    // Unread chat messages badge
    _chatBadgeSub = FirebaseFirestore.instance
        .collection('Chats')
        .doc(widget.coupleId)
        .collection('Messages')
        .where('receiverId', isEqualTo: myUid)
        .where('readStatus', isNotEqualTo: 'read')
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _unreadChats = snap.docs.length);
    }, onError: (_) {});

    // Missed calls badge
    _callBadgeSub = FirebaseFirestore.instance
        .collection('calls')
        .where('receiverId', isEqualTo: myUid)
        .where('status', isEqualTo: 'missed')
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _missedCalls = snap.docs.length);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chatBadgeSub?.cancel();
    _callBadgeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.coupleId.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border,
                color: Colors.white.withValues(alpha: 0.4), size: 64),
            const SizedBox(height: 16),
            Text(
              'No partner connected yet 💔',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7), fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Go to Wake tab to send a pairing request',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Column(
      children: [
        // ── Sub-tab bar (ViewPager2-style) ───────────────────────────
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(16),
            ),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle:
                const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            dividerColor: Colors.transparent,
            splashBorderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('💬 Chat'),
                    if (_unreadChats > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$_unreadChats',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('📞 Calls'),
                    if (_missedCalls > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$_missedCalls',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Tab(text: '📸 Media'),
              const Tab(text: '📊 Stats'),
            ],
          ),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.08, end: 0),

        // ── Sub-tab content ─────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              CoupleChat(
                coupleId: widget.coupleId,
                partnerId: _partnerId,
                partnerName: _partnerName.isNotEmpty
                    ? _partnerName
                    : (_partnerEmail.isNotEmpty
                        ? _partnerEmail.split('@').first
                        : 'Partner'),
              ),
              CoupleCalls(
                coupleId: widget.coupleId,
                partnerId: _partnerId,
                partnerName: _partnerName,
              ),
              CoupleMedia(coupleId: widget.coupleId),
              CoupleStats(coupleId: widget.coupleId),
            ],
          ),
        ),
      ],
    );
  }
}
