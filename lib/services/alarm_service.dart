import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../screens/alarm_screen.dart';

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

final GlobalKey<NavigatorState> alarmNavigatorKey = GlobalKey<NavigatorState>();

const MethodChannel _ultraAlarmChannel = MethodChannel('ultra_alarm');
const String _ultraAlarmPermsKey = 'ultra_alarm_perms_requested_v2';

bool _tzReady = false;

/// **Must** be called before any zonedSchedule() call.
/// Always initializes timezone data and sets the local location.
/// Falls back to 'Asia/Kolkata' if device timezone detection fails.
Future<void> _ensureTimeZoneReady() async {
  if (_tzReady) return;

  // Load ALL timezone definitions (required before getLocation / setLocalLocation).
  tz.initializeTimeZones();

  String tzName = 'Asia/Kolkata'; // safe fallback
  try {
    tzName = await FlutterTimezone.getLocalTimezone();
  } catch (e) {
    debugPrint('[timezone] FlutterTimezone.getLocalTimezone() failed: $e — using $tzName');
  }

  try {
    tz.setLocalLocation(tz.getLocation(tzName));
    debugPrint('[timezone] Local timezone set to $tzName');
  } catch (e) {
    // tzName from device was invalid; hard-fall to Asia/Kolkata.
    debugPrint('[timezone] getLocation($tzName) failed: $e — falling back to Asia/Kolkata');
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
  }

  _tzReady = true;
}

@pragma('vm:entry-point')
Future<void> showAlarmNotification() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await notificationsPlugin.initialize(initSettings);

  const androidDetails = AndroidNotificationDetails(
    'alarm_channel',
    'WakeUpDarling Alarm',
    importance: Importance.max,
    priority: Priority.high,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('alarm_sound'),
    enableVibration: true,
  );

  const details = NotificationDetails(android: androidDetails);

  await notificationsPlugin.show(
    0,
    'Wake-Up Darling 🔔',
    'Time to wake up!',
    details,
    payload: 'alarm',
  );
}

class AlarmService {
  static Future<void> initialize() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid) return;

    await _ensureTimeZoneReady();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) async {
        final payload = response.payload ?? '';
        int alarmId = 0;
        String coupleId = '';

        // Payload is either legacy 'alarm' string or JSON with alarmId+coupleId.
        if (payload != 'alarm' && payload.isNotEmpty) {
          try {
            final map = json.decode(payload) as Map<String, dynamic>;
            alarmId = (map['alarmId'] as int?) ?? 0;
            coupleId = (map['coupleId'] as String?) ?? '';
          } catch (_) {}
        }

        // Try to wake screen via native AlarmActivity (Ultra Pro).
        try {
          await _ultraAlarmChannel.invokeMethod('openAlarmActivity');
        } catch (_) {}

        // Always push Flutter AlarmScreen so Firestore cancel listener is active.
        final state = alarmNavigatorKey.currentState;
        if (state != null) {
          state.push(
            MaterialPageRoute(
              builder: (_) => AlarmScreen(alarmId: alarmId, coupleId: coupleId),
            ),
          );
        }
      },
    );

    // Request alarm-critical permissions once (guarded by SharedPrefs key).
    // Runs here so already-paired users are also covered on next launch.
    await requestPermissionsOnceAfterPairingAccepted();

    // Always (re-)request exact-alarm permission so Android 12+ devices that
    // revoked it after first install are prompted again on every launch.
    try {
      final androidPlugin = notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestExactAlarmsPermission();
    } catch (_) {}
  }

  static Future<void> requestPermissionsOnceAfterPairingAccepted() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid) return;

    final prefs = await SharedPreferences.getInstance();
    final already = prefs.getBool(_ultraAlarmPermsKey) ?? false;
    if (already) return;
    await prefs.setBool(_ultraAlarmPermsKey, true);

    final androidPlugin = notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();

    try {
      await _ultraAlarmChannel.invokeMethod('requestDndAccessIfNeeded');
    } catch (_) {
      // Ignore if native side isn't available.
    }

    try {
      await _ultraAlarmChannel.invokeMethod('requestBatteryOptimizationExemption');
    } catch (_) {
      // Ignore if native side isn't available.
    }
  }

  static Future<void> scheduleAlarm(
    DateTime alarmTime, {
    int alarmId = 0,
    String coupleId = '',
    bool isEmergency = false,
  }) async {
    if (kIsWeb) return;
    if (!Platform.isAndroid) return;

    await _ensureTimeZoneReady();

    // Always request exact-alarm permission before scheduling.
    try {
      final androidPlugin = notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestExactAlarmsPermission();
    } catch (_) {}

    final scheduled = tz.TZDateTime.from(alarmTime, tz.local);
    debugPrint('[scheduleAlarm] Scheduling at $scheduled  id=$alarmId  coupleId=$coupleId  emergency=$isEmergency');

    final payload = (alarmId == 0 && coupleId.isEmpty)
        ? 'alarm'
        : json.encode({'alarmId': alarmId, 'coupleId': coupleId});

    const androidDetails = AndroidNotificationDetails(
      'alarm_channel',
      'Alarm Channel',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
    );

    const details = NotificationDetails(android: androidDetails);

    final title =
        isEmergency ? '🚨 Emergency Wake!' : 'Wake Up Darling 💖';
    final body = isEmergency
        ? 'Your partner triggered an emergency wake-up!'
        : 'Your partner is waking you!';

    await notificationsPlugin.zonedSchedule(
      alarmId,
      title,
      body,
      scheduled,
      details,
      payload: payload,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );

    debugPrint('[scheduleAlarm] Alarm scheduled for $scheduled');
  }

  /// Cancel a scheduled or active notification by its ID.
  static Future<void> cancelAlarm(int alarmId) async {
    if (kIsWeb) return;
    if (!Platform.isAndroid) return;
    await notificationsPlugin.cancel(alarmId);
  }

  // ── Firestore couple-alarm helpers ─────────────────────────────────────────

  static final _db = FirebaseFirestore.instance;

  /// Write (or overwrite) the alarm sub-doc on the couple document.
  /// Also updates the per-user alarm status for partner visibility.
  static Future<void> saveAlarmRecord({
    required String coupleId,
    required int alarmId,
    required DateTime time,
    required String createdByUid,
  }) async {
    if (coupleId.isEmpty) return;
    await _db.collection('couples').doc(coupleId).set(
      {
        'alarm': {
          'id': alarmId,
          'time': Timestamp.fromDate(time),
          'createdBy': createdByUid,
          'status': 'scheduled',
        },
        // Track per-user alarm status so partner can see it in stats.
        'alarmStatuses': {
          createdByUid: {
            'active': true,
            'lastUpdated': Timestamp.now(),
          },
        },
      },
      SetOptions(merge: true),
    );
  }

  /// Update only the status field of the couple alarm sub-doc.
  /// Also updates the per-user alarm status when completed/cancelled.
  static Future<void> updateCoupleAlarmStatus({
    required String coupleId,
    required String status,
  }) async {
    if (coupleId.isEmpty) return;
    try {
      final updateData = <String, dynamic>{
        'alarm.status': status,
      };

      // If alarm is completed, cancelled, or ignored, clear the user's active flag.
      if (['completed', 'cancelled', 'ignored', 'woke'].contains(status)) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          updateData['alarmStatuses.$uid.active'] = false;
          updateData['alarmStatuses.$uid.lastUpdated'] = Timestamp.now();
        }
      }

      await _db.collection('couples').doc(coupleId).update(updateData);
    } catch (_) {
      // Document may not have an alarm field yet; ignore.
    }
  }

  /// Real-time stream of the couple document (used for remote cancel listener).
  static Stream<DocumentSnapshot<Map<String, dynamic>>> streamCoupleDoc(
      String coupleId) {
    if (coupleId.isEmpty) return const Stream.empty();
    return _db.collection('couples').doc(coupleId).snapshots();
  }

  /// Fetch the current user's coupleId from their profile document.
  static Future<String> fetchCurrentUserCoupleId() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return '';
    final snap = await _db.collection('users').doc(uid).get();
    return (snap.data()?['coupleId'] ?? '').toString().trim();
  }

  /// Fire an IMMEDIATE full-screen alarm notification.
  /// Used by the FCM background handler when an emergency_wake message
  /// arrives so the alarm rings even in silent / DND mode.
  static Future<void> triggerEmergencyAlarm() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid) return;

    await initialize();

    // Schedule 4 seconds from now – enough time for the isolate to start
    // the notification service, but immediate from the user's perspective.
    final ringAt = DateTime.now().add(const Duration(seconds: 4));
    await scheduleAlarm(
      ringAt,
      alarmId: 88888,
      isEmergency: true,
    );
    debugPrint('[AlarmService] triggerEmergencyAlarm → ring at $ringAt');
  }
}
