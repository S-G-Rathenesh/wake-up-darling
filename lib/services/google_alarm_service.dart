import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart';

class GoogleAlarmService {
  /// Sets an alarm in Google Clock at the given [hour] and [minute].
  static Future<void> setAlarm({
    required int hour,
    required int minute,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;

    final intent = AndroidIntent(
      action: 'android.intent.action.SET_ALARM',
      arguments: {
        'android.intent.extra.alarm.HOUR': hour,
        'android.intent.extra.alarm.MINUTES': minute,
        'android.intent.extra.alarm.MESSAGE': 'Wake Up Darling ❤️',
        'android.intent.extra.alarm.SKIP_UI': true,
      },
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
    );

    await intent.launch();
    debugPrint('[GoogleAlarmService] SET_ALARM intent fired for $hour:$minute');
  }

  /// Sets an alarm in Google Clock at the provided [time].
  static Future<void> triggerAlarmAtTime(DateTime time) async {
    if (kIsWeb || !Platform.isAndroid) return;

    final intent = AndroidIntent(
      action: 'android.intent.action.SET_ALARM',
      arguments: {
        'android.intent.extra.alarm.HOUR': time.hour,
        'android.intent.extra.alarm.MINUTES': time.minute,
        'android.intent.extra.alarm.MESSAGE': 'Wake Up Darling ❤️',
        'android.intent.extra.alarm.SKIP_UI': true,
      },
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
    );

    await intent.launch();
    debugPrint(
        '[GoogleAlarmService] SET_ALARM intent fired for ${time.hour}:${time.minute}');
  }

  /// Emergency variant — sets alarm to 1 minute from now.
  static Future<void> triggerEmergencyNow() async {
    if (kIsWeb || !Platform.isAndroid) return;

    final now = DateTime.now().add(const Duration(minutes: 1));
    await setAlarm(hour: now.hour, minute: now.minute);
  }
}
