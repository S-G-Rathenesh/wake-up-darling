import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/wake_request_model.dart';
import '../widgets/romantic_hearts_overlay.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/user_service.dart';

class SetAlarmScreen extends StatefulWidget {
  const SetAlarmScreen({super.key});

  @override
  State<SetAlarmScreen> createState() => _SetAlarmScreenState();
}

class _SetAlarmScreenState extends State<SetAlarmScreen> {
  TimeOfDay? selectedTime;
  final FirestoreService _firestore = FirestoreService();
  final AuthService _auth = AuthService();
  final UserService _userService = UserService();

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
                        'Set Wake Alarm ⏰',
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
                child: StreamBuilder(
                  stream: _userService.getCurrentUserProfile(),
                  builder: (context, snapshot) {
                    final data = snapshot.data?.data() ?? <String, dynamic>{};
                    final partnerEmail = (data['partnerEmail'] ?? '').toString().trim();
                    final partnerUid = (data['partnerId'] ?? '').toString().trim();

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              partnerEmail.isEmpty
                                  ? 'Connect a partner first 💜'
                                  : 'Waking: $partnerEmail',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 14),
                            InkWell(
                              borderRadius: BorderRadius.circular(30),
                              onTap: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.now(),
                                );
                                if (!context.mounted) return;
                                selectedTime = picked;
                                setState(() {});
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.20),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.18),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    selectedTime == null
                                        ? 'Select Wake Time'
                                        : 'Selected: ${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            InkWell(
                              borderRadius: BorderRadius.circular(30),
                              onTap: selectedTime == null || partnerEmail.isEmpty
                                  ? null
                                  : () async {
                                      final currentUid = _auth.currentUser?.uid;
                                      if (currentUid == null || currentUid.isEmpty) return;
                                      if (partnerUid.isEmpty) return;

                                      final now = DateTime.now();
                                      final scheduledDateTime = DateTime(
                                        now.year,
                                        now.month,
                                        now.day,
                                        selectedTime!.hour,
                                        selectedTime!.minute,
                                      );

                                      final request = WakeRequest(
                                        createdBy: currentUid,
                                        target: partnerUid,
                                        scheduledTime: scheduledDateTime,
                                        status: 'pending',
                                        createdAt: DateTime.now(),
                                      );

                                      await _firestore.sendWakeRequest(request);
                                      if (!context.mounted) return;

                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Wake Request Sent 🔔')),
                                      );
                                    },
                              child: Opacity(
                                opacity: selectedTime == null || partnerEmail.isEmpty ? 0.5 : 1,
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
                                      'Send Wake Request',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(
                        duration: const Duration(milliseconds: 450),
                      ).slideY(
                        begin: 0.10,
                        end: 0,
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOut,
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
