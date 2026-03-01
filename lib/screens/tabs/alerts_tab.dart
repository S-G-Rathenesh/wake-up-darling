import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/google_alarm_service.dart';
import '../../widgets/animated_empty_state.dart';

/// The "Alerts" tab — shows pending incoming wake requests with accept/reject.
/// This is the same content as IncomingRequestsScreen, adapted to work
/// as an embedded tab (no Scaffold / no back button).
class AlertsTab extends StatelessWidget {
  const AlertsTab({super.key});

  String formatTime(DateTime time) => DateFormat('h:mm a').format(time);

  Widget _createdByEmail(String uid) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        final email = snapshot.data?.data()?['email']?.toString();
        return Text(
          (email == null || email.isEmpty) ? uid : email,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        );
      },
    );
  }

  Widget _glassButton({
    required String label,
    required VoidCallback? onTap,
    required IconData icon,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserUid == null || currentUserUid.isEmpty) {
      return const Center(
        child: Text('Not logged in', style: TextStyle(color: Colors.white)),
      );
    }

    return Column(
      children: [
        const SizedBox(height: 16),
        const Text(
          'Incoming Wake Alerts 💌',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('wake_requests')
                .where('target', isEqualTo: currentUserUid)
                .where('status', isEqualTo: 'pending')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }

              final requests = snapshot.data!.docs;

              if (requests.isEmpty) {
                return const AnimatedEmptyState(
                  icon: Icons.notifications_off_outlined,
                  message: 'No pending requests',
                );
              }

              return ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                itemCount: requests.length,
                itemBuilder: (context, index) {
                  final doc = requests[index];
                  final request = doc.data() as Map<String, dynamic>;

                  final createdBy = (request['createdBy'] ?? '').toString();
                  final scheduledTime =
                      (request['scheduledTime'] as Timestamp).toDate();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(26),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _createdByEmail(createdBy),
                          const SizedBox(height: 6),
                          Text(
                            'Wake Time: ${formatTime(scheduledTime)}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.90),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _glassButton(
                                label: 'Accept',
                                icon: Icons.check,
                                onTap: () async {
                                  final scheduledTime =
                                      (request['scheduledTime'] as Timestamp)
                                          .toDate();

                                  await GoogleAlarmService.triggerAlarmAtTime(
                                      scheduledTime);

                                  await doc.reference.update({
                                    'status': 'approved',
                                  });
                                },
                              ),
                              const SizedBox(width: 12),
                              _glassButton(
                                label: 'Reject',
                                icon: Icons.close,
                                onTap: () async {
                                  await doc.reference.update({
                                    'status': 'rejected',
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
