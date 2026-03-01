import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// Top-level function that AndroidAlarmManager can invoke in a separate isolate.
/// It fires an immediate high-priority notification that wakes the screen.
@pragma('vm:entry-point')
Future<void> triggerPartnerAlarm() async {
  // Ensure the plugin is initialized in this isolate.
  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'wake_channel',
    'Wake Alarm',
    importance: Importance.max,
    priority: Priority.high,
    fullScreenIntent: true,
    playSound: true,
    enableVibration: true,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
  );

  const NotificationDetails details =
      NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.show(
    0,
    'Wake Up Darling ❤️',
    'Your partner is waking you!',
    details,
  );
}
