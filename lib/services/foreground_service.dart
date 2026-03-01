import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

import '../firebase_options.dart';
import 'alarm_service.dart';
import 'alarm_listener_service.dart';

/// Manages the persistent foreground service that keeps the app alive
/// in the background so Firestore listeners remain active at all times.
class WakeForegroundService {
  static void initService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'wake_channel',
        channelName: 'Wake Background Service',
        channelDescription: 'Keeps wake listener active',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: true,
        allowWakeLock: true,
      ),
    );
  }

  static Future<void> startService() async {
    if (await FlutterForegroundTask.isRunningService) return;

    await FlutterForegroundTask.startService(
      notificationTitle: 'Wake-Up Darling 💜',
      notificationText: 'Running in background',
      callback: _startCallback,
    );
  }
}

@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_WakeTaskHandler());
}

class _WakeTaskHandler extends TaskHandler {
  @override
  void onStart(DateTime timestamp, SendPort? sendPort) {
    // Ensure Firebase + timezone + alarm listeners are running.
    // Critical for the autoRunOnBoot path where main() does NOT execute.
    _bootstrapAndListen();
  }

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {
    // Heartbeat every 5 s — restart Firestore listeners if they died.
    // Guard against Firebase not being initialized (e.g. boot path).
    try {
      Firebase.app(); // throws if not initialized
      AlarmListenerService.instance.start();
    } catch (_) {
      // Firebase not ready yet — _bootstrapAndListen will handle it.
    }
  }

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) {
    AlarmListenerService.instance.stop();
  }
}

Future<void> _bootstrapAndListen() async {
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {
    // Already initialized when the normal app is running.
  }

  // Timezone init (needed by AlarmService.scheduleAlarm).
  try {
    tz.initializeTimeZones();
    final tzName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzName));
  } catch (_) {
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (_) {}
  }

  // Initialize AlarmService (notification channels etc.).
  try {
    await AlarmService.initialize();
  } catch (e) {
    debugPrint('[ForegroundService] AlarmService.initialize failed: $e');
  }

  // Start global Firestore alarm listeners.
  await AlarmListenerService.instance.start();
  debugPrint('[ForegroundService] bootstrap complete');
}

