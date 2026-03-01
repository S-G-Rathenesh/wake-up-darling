import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

import 'alarm_service.dart';
import 'google_alarm_service.dart';
import 'background_alarm_service.dart';

/// Global singleton that listens to the couple document in Firestore and
/// schedules / triggers alarms on this device.  Runs independently of any
/// Flutter screen so that alarms are received even when the app is in the
/// background (foreground service keeps the process alive).
class AlarmListenerService {
  AlarmListenerService._();
  static final AlarmListenerService _instance = AlarmListenerService._();
  static AlarmListenerService get instance => _instance;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _alarmSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _remoteSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _voiceWakeSub;
  String _coupleId = '';
  bool _running = false;

  /// The coupleId this listener is attached to (visible to screens).
  String get coupleId => _coupleId;

  /// Start listening.  Safe to call multiple times — will no-op if already
  /// running for the same couple.
  Future<void> start() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    final id = await AlarmService.fetchCurrentUserCoupleId();
    if (id.isEmpty) return;

    // Already listening to the same couple.
    if (_running && _coupleId == id) return;

    // Different couple (or first start) → tear down old subs.
    stop();

    _coupleId = id;
    _running = true;

    _startAlarmListener(uid);
    _startRemoteAlarmListener(uid);
    _startVoiceWakeListener(uid);

    debugPrint('[AlarmListenerService] Started for coupleId=$_coupleId  uid=$uid');
  }

  /// Stop all listeners (e.g. on logout).
  void stop() {
    _alarmSub?.cancel();
    _alarmSub = null;
    _remoteSub?.cancel();
    _remoteSub = null;
    _voiceWakeSub?.cancel();
    _voiceWakeSub = null;
    _running = false;
    debugPrint('[AlarmListenerService] Stopped');
  }

  // ── Main alarm listener (scheduled + emergency) ──────────────────────────

  void _startAlarmListener(String myUid) {
    _alarmSub?.cancel();
    _alarmSub = AlarmService.streamCoupleDoc(_coupleId).listen(
      (snapshot) async {
        if (!snapshot.exists) return;
        final data = snapshot.data();

        final alarm = data?['alarm'] as Map<String, dynamic>?;
        if (alarm == null) return;

        final status = (alarm['status'] ?? '').toString();
        final createdBy = (alarm['createdBy'] ?? '').toString();

        // ── Emergency wake ─────────────────────────────────────────────
        if (status == 'emergency' &&
            createdBy != myUid &&
            (alarm['target'] ?? '') == myUid) {
          debugPrint('[AlarmListenerService] Remote emergency detected');
          try {
            await GoogleAlarmService.triggerEmergencyNow();
          } catch (e) {
            debugPrint('[AlarmListenerService] GoogleAlarm emergency failed: $e');
          }
          try {
            await AlarmService.triggerEmergencyAlarm();
          } catch (e) {
            debugPrint('[AlarmListenerService] triggerEmergencyAlarm failed: $e');
          }
          await FirebaseFirestore.instance
              .collection('couples')
              .doc(_coupleId)
              .update({'alarm.status': 'completed'});
          return;
        }

        // ── Scheduled alarm ────────────────────────────────────────────
        if (status != 'scheduled' || createdBy == myUid) return;

        final timeRaw = alarm['time'];
        if (timeRaw == null) return;
        var alarmTime = (timeRaw as Timestamp).toDate();
        final alarmId = (alarm['id'] as int?) ?? 0;

        if (alarmTime.isBefore(DateTime.now())) {
          debugPrint('[AlarmListenerService] alarmTime in the past — scheduling in 20 s');
          alarmTime = DateTime.now().add(const Duration(seconds: 20));
        }

        debugPrint('[AlarmListenerService] Scheduling alarm at $alarmTime  id=$alarmId');

        // Mark triggered FIRST to prevent double-fire on next snapshot.
        await AlarmService.updateCoupleAlarmStatus(
          coupleId: _coupleId,
          status: 'triggered',
        );

        // 1) Set Google Clock alarm so the phone rings natively.
        try {
          await GoogleAlarmService.triggerAlarmAtTime(alarmTime);
        } catch (e) {
          debugPrint('[AlarmListenerService] GoogleAlarm scheduled failed: $e');
        }

        // 2) Also schedule a notification alarm as backup.
        try {
          await AlarmService.scheduleAlarm(
            alarmTime,
            alarmId: alarmId,
            coupleId: _coupleId,
          );
          debugPrint('[AlarmListenerService] scheduleAlarm succeeded');
        } catch (e, st) {
          debugPrint('[AlarmListenerService] scheduleAlarm FAILED: $e\n$st');
        }

        // 3) AndroidAlarmManager: fires even if app is killed / removed from recents.
        try {
          final delay = alarmTime.difference(DateTime.now());
          final secs = delay.inSeconds > 2 ? delay.inSeconds : 2;
          await AndroidAlarmManager.oneShot(
            Duration(seconds: secs),
            alarmId,
            triggerPartnerAlarm,
            exact: true,
            wakeup: true,
          );
          debugPrint('[AlarmListenerService] AndroidAlarmManager.oneShot scheduled in ${secs}s');
        } catch (e) {
          debugPrint('[AlarmListenerService] AndroidAlarmManager FAILED: $e');
        }
      },
      onError: (e) {
        debugPrint('[AlarmListenerService] alarm listener error: $e');
      },
    );
  }

  // ── Remote Google-Clock alarm listener ────────────────────────────────────

  void _startRemoteAlarmListener(String myUid) {
    _remoteSub?.cancel();
    _remoteSub = AlarmService.streamCoupleDoc(_coupleId).listen(
      (snapshot) async {
        if (!snapshot.exists) return;
        final data = snapshot.data();
        final remote = data?['remoteAlarm'] as Map<String, dynamic>?;
        if (remote == null) return;

        final status = (remote['status'] ?? '').toString();
        if (status != 'pending') return;

        final createdBy = (remote['createdBy'] ?? '').toString();
        if (createdBy == myUid) return;

        final hour = (remote['hour'] as int?) ?? 0;
        final minute = (remote['minute'] as int?) ?? 0;

        debugPrint('[AlarmListenerService] RemoteAlarm triggering Google Clock $hour:$minute');

        final coupleRef =
            FirebaseFirestore.instance.collection('couples').doc(_coupleId);

        try {
          await coupleRef.update({
            'remoteAlarm.status': 'applying',
            'remoteAlarm.applyingAt': Timestamp.now(),
            'remoteAlarm.appliedBy': myUid,
          });
        } catch (_) {}

        try {
          await GoogleAlarmService.setAlarm(hour: hour, minute: minute);
          await coupleRef.update({
            'remoteAlarm.status': 'completed',
            'remoteAlarm.appliedAt': Timestamp.now(),
            'remoteAlarm.appliedBy': myUid,
          });
        } catch (e) {
          debugPrint('[AlarmListenerService] setAlarm FAILED: $e');
          try {
            await coupleRef.update({
              'remoteAlarm.status': 'failed',
              'remoteAlarm.failedAt': Timestamp.now(),
              'remoteAlarm.error': e.toString(),
              'remoteAlarm.appliedBy': myUid,
            });
          } catch (_) {}
        }
      },
      onError: (e) {
        debugPrint('[AlarmListenerService] remote alarm listener error: $e');
      },
    );
  }

  // ── Voice Wake listener ───────────────────────────────────────────────────

  void _startVoiceWakeListener(String myUid) {
    _voiceWakeSub?.cancel();
    _voiceWakeSub = AlarmService.streamCoupleDoc(_coupleId).listen(
      (snapshot) async {
        if (!snapshot.exists) return;
        final data = snapshot.data();
        final voiceWake = data?['voiceWake'] as Map<String, dynamic>?;
        if (voiceWake == null) return;

        final status = (voiceWake['status'] ?? '').toString();
        if (status != 'pending') return;

        final receiverId = (voiceWake['receiverId'] ?? '').toString();
        // Only process if this device is the intended receiver.
        if (receiverId != myUid) return;

        final voiceUrl = (voiceWake['voiceUrl'] ?? '').toString();
        final scheduledTimeMs = (voiceWake['scheduledTimeMs'] as int?) ?? 0;

        debugPrint('[AlarmListenerService] Voice wake received — url=$voiceUrl  scheduledMs=$scheduledTimeMs');

        final coupleRef =
            FirebaseFirestore.instance.collection('couples').doc(_coupleId);

        // Mark as triggered to prevent double-fire.
        try {
          await coupleRef.update({
            'voiceWake.status': 'triggered',
          });
        } catch (_) {}

        // Calculate alarm time.
        DateTime alarmTime;
        if (scheduledTimeMs > 0) {
          alarmTime = DateTime.fromMillisecondsSinceEpoch(scheduledTimeMs);
          if (alarmTime.isBefore(DateTime.now())) {
            debugPrint('[AlarmListenerService] Voice wake time in past — scheduling in 10s');
            alarmTime = DateTime.now().add(const Duration(seconds: 10));
          }
        } else {
          // No scheduled time → ring immediately (10s from now).
          alarmTime = DateTime.now().add(const Duration(seconds: 10));
        }

        final alarmId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        // 1) Set Google Clock alarm.
        try {
          await GoogleAlarmService.triggerAlarmAtTime(alarmTime);
        } catch (e) {
          debugPrint('[AlarmListenerService] GoogleAlarm voice wake failed: $e');
        }

        // 2) Schedule notification alarm.
        try {
          await AlarmService.scheduleAlarm(
            alarmTime,
            alarmId: alarmId,
            coupleId: _coupleId,
          );
        } catch (e) {
          debugPrint('[AlarmListenerService] scheduleAlarm voice wake failed: $e');
        }

        // 3) AndroidAlarmManager as backup.
        try {
          final delay = alarmTime.difference(DateTime.now());
          final secs = delay.inSeconds > 2 ? delay.inSeconds : 2;
          await AndroidAlarmManager.oneShot(
            Duration(seconds: secs),
            alarmId,
            triggerPartnerAlarm,
            exact: true,
            wakeup: true,
          );
        } catch (e) {
          debugPrint('[AlarmListenerService] AndroidAlarmManager voice wake failed: $e');
        }

        // Update Firestore status.
        try {
          await coupleRef.update({
            'voiceWake.status': 'completed',
            'alarm': {
              'id': alarmId,
              'status': 'active',
              'createdBy': voiceWake['senderId'] ?? '',
              'target': myUid,
              'time': Timestamp.fromDate(alarmTime),
              'voiceUrl': voiceUrl,
            },
          });
        } catch (e) {
          debugPrint('[AlarmListenerService] voiceWake status update failed: $e');
        }

        debugPrint('[AlarmListenerService] Voice wake alarm scheduled at $alarmTime');
      },
      onError: (e) {
        debugPrint('[AlarmListenerService] voice wake listener error: $e');
      },
    );
  }
}
