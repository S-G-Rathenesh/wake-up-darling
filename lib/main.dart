import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

import 'firebase_options.dart';
import 'dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/incoming_call_screen.dart';
import 'services/alarm_service.dart';
import 'services/alarm_listener_service.dart';
import 'services/chat_service.dart';
import 'services/user_service.dart';
import 'models/call_model.dart';

/// Top-level (isolate-safe) FCM background handler.
/// Called by the Firebase plugin when a data message arrives while the
/// app is terminated or in the background.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Must call this before any Firebase usage in a background isolate.
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final type = message.data['type'] ?? '';

  if (type == 'emergency_wake') {
    // Initialise AlarmService (also sets up notification channel).
    await AlarmService.initialize();
    // Fire an immediate full-screen alarm notification overriding silent/DND.
    await AlarmService.triggerEmergencyAlarm();
  } else if (type == 'scheduled_alarm') {
    // Partner set an alarm for us — schedule it even though the app is killed.
    await AlarmService.initialize();
    final coupleId = message.data['coupleId'] ?? '';
    final alarmId = int.tryParse(message.data['alarmId'] ?? '0') ?? 0;
    final alarmTimeMs =
        int.tryParse(message.data['alarmTimeMs'] ?? '0') ?? 0;

    var alarmTime = alarmTimeMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(alarmTimeMs)
        : DateTime.now().add(const Duration(seconds: 20));

    // If the time has already passed, schedule 20 s from now.
    if (alarmTime.isBefore(DateTime.now())) {
      alarmTime = DateTime.now().add(const Duration(seconds: 20));
    }

    await AlarmService.scheduleAlarm(
      alarmTime,
      alarmId: alarmId,
      coupleId: coupleId,
    );

    // Mark as triggered so the sender knows the partner received it.
    if (coupleId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('couples')
            .doc(coupleId)
            .update({'alarm.status': 'triggered'});
      } catch (_) {}
    }
  } else if (type == 'voice_wake') {
    // ── V2: Voice wake request received in background ────────────────────
    await AlarmService.initialize();
    final coupleId = message.data['coupleId'] ?? '';
    final alarmTimeMs =
        int.tryParse(message.data['scheduledTimeMs'] ?? '0') ?? 0;
    // voiceUrl is stored in Firestore and used by the alarm screen.
    final senderName = message.data['senderName'] ?? 'Partner';

    var alarmTime = alarmTimeMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(alarmTimeMs)
        : DateTime.now().add(const Duration(seconds: 30));

    if (alarmTime.isBefore(DateTime.now())) {
      alarmTime = DateTime.now().add(const Duration(seconds: 20));
    }

    // Check college time (8:00 AM – 5:30 PM): save as request only.
    final now = DateTime.now();
    final collegeStart = DateTime(now.year, now.month, now.day, 8, 0);
    final collegeEnd = DateTime(now.year, now.month, now.day, 17, 30);
    final isCollege = now.isAfter(collegeStart) && now.isBefore(collegeEnd);

    if (!isCollege) {
      // Schedule exact alarm.
      final alarmId = DateTime.now().millisecondsSinceEpoch % 100000;
      await AlarmService.scheduleAlarm(
        alarmTime,
        alarmId: alarmId,
        coupleId: coupleId,
      );

      // Show notification.
      await notificationsPlugin.show(
        99999,
        '$senderName set alarm for you ❤️',
        'Voice wake at ${alarmTime.hour}:${alarmTime.minute.toString().padLeft(2, '0')}',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'alarm_channel',
            'WakeUpDarling Alarm',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    }
    // College hours: request is already saved in Firestore by the sender.
  } else if (type == 'incoming_call') {
    // ── V2: Incoming call notification in background ─────────────────────
    final callerName = message.data['callerName'] ?? 'Partner';
    final callType = message.data['callType'] ?? 'voice';

    await AlarmService.initialize();
    await notificationsPlugin.show(
      77777,
      '$callerName is calling... ${callType == 'video' ? '📹' : '📞'}',
      'Tap to open app',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'call_channel',
          'Incoming Calls',
          importance: Importance.max,
          priority: Priority.high,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
          visibility: NotificationVisibility.public,
        ),
      ),
    );
  } else if (type == 'chat_message') {
    // ── V2: Chat message notification in background ──────────────────────
    final senderName = message.data['senderName'] ?? 'Partner';
    final text = message.data['text'] ?? '💌 New message';

    await AlarmService.initialize();
    await notificationsPlugin.show(
      66666,
      senderName,
      text,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'chat_channel',
          'Chat Messages',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Timezone init (MUST happen before any zonedSchedule call) ──────────────
  tz.initializeTimeZones();
  try {
    final tzName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzName));
  } catch (_) {
    // Device timezone lookup failed — fall back to Asia/Kolkata.
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
  }
  // ───────────────────────────────────────────────────────────────────────────

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize AndroidAlarmManager (must be after ensureInitialized).
  await AndroidAlarmManager.initialize();

  // Register background FCM handler BEFORE calling any other Firebase API.
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await FirebaseMessaging.instance.requestPermission();
  await AlarmService.initialize();

  // Explicit plugin initialization (belt-and-suspenders alongside AlarmService).
  await notificationsPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final userService = UserService();
  StreamSubscription<User?>? _authSub;

  static const _fallbackSeedColor = Color(0xFF7E57C2);
  ColorScheme? _logoColorScheme;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _loadThemeFromLogo();

    // Handle FCM messages while app is in the FOREGROUND.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final type = message.data['type'] ?? '';
      if (type == 'emergency_wake') {
        AlarmService.triggerEmergencyAlarm();
      } else if (type == 'scheduled_alarm') {
        // AlarmListenerService (Firestore snapshot listener) handles the
        // actual scheduling, so we only show a heads-up notification here
        // to avoid double-scheduling the same alarm.
        final alarmTimeMs =
            int.tryParse(message.data['alarmTimeMs'] ?? '0') ?? 0;
        final alarmTime = alarmTimeMs > 0
            ? DateTime.fromMillisecondsSinceEpoch(alarmTimeMs)
            : DateTime.now().add(const Duration(seconds: 20));
        notificationsPlugin.show(
          99998,
          'Alarm set by partner ❤️',
          'Wake up at ${alarmTime.hour}:${alarmTime.minute.toString().padLeft(2, '0')}',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'alarm_channel',
              'WakeUpDarling Alarm',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
      } else if (type == 'voice_wake') {
        // V2: Voice wake received while app is open.
        final senderName = message.data['senderName'] ?? 'Partner';
        notificationsPlugin.show(
          99999,
          '$senderName sent a voice wake ❤️',
          'Tap to listen',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'alarm_channel',
              'WakeUpDarling Alarm',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
      } else if (type == 'incoming_call') {
        // V2: Incoming call while app is in foreground — navigate to call screen.
        final callId = message.data['callId'] ?? '';
        final callerName = message.data['callerName'] ?? 'Partner';
        final callType = message.data['callType'] ?? 'voice';
        final coupleId = message.data['coupleId'] ?? '';
        if (callId.isNotEmpty && alarmNavigatorKey.currentState != null) {
          final call = CallModel(
            id: callId,
            callerId: '',
            callerName: callerName,
            receiverId: FirebaseAuth.instance.currentUser?.uid ?? '',
            receiverName: '',
            coupleId: coupleId,
            type: callType,
            status: 'calling',
            timestamp: DateTime.now(),
          );
          alarmNavigatorKey.currentState!.push(
            MaterialPageRoute(
              builder: (_) => IncomingCallScreen(
                call: call,
              ),
            ),
          );
        }
      } else if (type == 'chat_message') {
        // V2: Chat message while app is open — show subtle notification.
        final senderName = message.data['senderName'] ?? 'Partner';
        final text = message.data['text'] ?? '💌 New message';
        notificationsPlugin.show(
          66666,
          senderName,
          text,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'chat_channel',
              'Chat Messages',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
          ),
        );
      }
    });

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        userService.setOnlineStatus(true);
        // Start global Firestore alarm listener so alarms are received
        // even when the app is backgrounded / on a different screen.
        AlarmListenerService.instance.start();

        // V2: Save FCM token for push notifications to this device.
        FirebaseMessaging.instance.getToken().then((token) {
          if (token != null) {
            FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .update({'fcmToken': token}).catchError((_) {});
          }
        });

        // V2: Listen for FCM token refresh so we never have a stale token.
        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) {
            FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .update({'fcmToken': newToken}).catchError((_) {});
          }
        });

        // V2: Set online status for Chat.
        ChatService().setOnlineStatus(true);
      } else {
        AlarmListenerService.instance.stop();
      }
    });
  }

  Future<void> _loadThemeFromLogo() async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        const AssetImage('logo.png'),
        maximumColorCount: 12,
      );

      final seed = palette.dominantColor?.color ?? _fallbackSeedColor;
      if (!mounted) return;
      setState(() {
        _logoColorScheme = ColorScheme.fromSeed(seedColor: seed);
      });
    } catch (_) {
      // Keep fallback theme if palette generation fails.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    userService.setOnlineStatus(false);
    ChatService().setOnlineStatus(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final chatService = ChatService();
    if (state == AppLifecycleState.paused) {
      userService.setOnlineStatus(false);
      chatService.setOnlineStatus(false);
    } else if (state == AppLifecycleState.resumed) {
      userService.setOnlineStatus(true);
      chatService.setOnlineStatus(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        _logoColorScheme ?? ColorScheme.fromSeed(seedColor: _fallbackSeedColor);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.15),
          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.80)),
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.60)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      navigatorKey: alarmNavigatorKey,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          // Run profile setup in background — navigate immediately.
          Future.microtask(
            () => UserService().ensureUserProfileExists(user: snapshot.data!),
          );
          return const DashboardScreen();
        }

        return const LoginScreen();
      },
    );
  }
}
