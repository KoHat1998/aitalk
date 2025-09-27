// lib/core/push_service.dart
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:audioplayers/audioplayers.dart';

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage m) async {
  try { await Firebase.initializeApp(); } catch (_) {}

  if ((m.data['type'] ?? '') != 'call') return;

  final callType = (m.data['callType'] ?? 'audio') as String;
  final caller   = (m.data['senderName'] ?? 'Someone') as String;
  final route    = (m.data['route'] ?? '') as String;
  final callId   = (m.data['callId'] ?? '') as String;
  final notifId  = callId.isNotEmpty ? callId.hashCode : DateTime.now().millisecondsSinceEpoch ~/ 1000;

  final fln = FlutterLocalNotificationsPlugin();
  final androidImpl = fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  // Channels (call channel plays res/raw/ringtone.mp3)
  await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
    'default_channel', 'General',
    description: 'Default chat notifications',
    importance: Importance.defaultImportance,
  ));
  await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
    'call_channel_v2', 'Calls',
    description: 'Incoming calls',
    importance: Importance.max,
    sound: RawResourceAndroidNotificationSound('ringtone'), // <-- res/raw/ringtone.mp3
    playSound: true,
  ));

  await fln.show(
    notifId,
    '$caller is ${callType == 'video' ? 'video ' : ''}calling you',
    'Tap to answer',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'call_channel_v2', 'Calls',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        ongoing: true,
        visibility: NotificationVisibility.public,
      ),
      iOS: DarwinNotificationDetails(presentSound: true),
    ),
    payload: route,
  );
}

class PushService {
  static final _fln = FlutterLocalNotificationsPlugin();
  static final AudioPlayer _ringPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.loop);
  static Timer? _ringTimer;

  static Future<void> init({
    void Function(String route)? onOpenRoute,
    void Function(RemoteMessage m)? onForegroundMessage,
  }) async {
    await Firebase.initializeApp();

    // ✅ Correct AudioContext usage (no const + correct enum names)
    await AudioPlayer.global.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: [
            AVAudioSessionOptions.defaultToSpeaker,
            AVAudioSessionOptions.mixWithOthers,
          ],
        ),
        android: AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.notification,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ),
    );

    await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
    FirebaseMessaging.onBackgroundMessage(_bgHandler);

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _fln.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        stopRingtone();
        final route = resp.payload;
        if (route != null && route.isNotEmpty) onOpenRoute?.call(route);
      },
    );

    final androidImpl = _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
      'default_channel', 'General',
      description: 'Default chat notifications',
      importance: Importance.defaultImportance,
    ));
    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
      'call_channel_v2', 'Calls',
      description: 'Incoming calls',
      importance: Importance.max,
      sound: RawResourceAndroidNotificationSound('ringtone'), // <-- res/raw/ringtone.mp3
      playSound: true,
    ));

    FirebaseMessaging.onMessage.listen((m) async {
      final myId = Supabase.instance.client.auth.currentUser?.id;
      final senderId = m.data['senderId'];
      if (myId != null && senderId != null && senderId == myId) return;

      final isCall = (m.data['type'] ?? '') == 'call';
      if (isCall) {
        await startRingtone(timeout: const Duration(seconds: 45));

        final callType = (m.data['callType'] ?? 'audio') as String;
        final caller   = (m.data['senderName'] ?? 'Someone') as String;
        final route    = (m.data['route'] ?? '') as String;
        final callId   = (m.data['callId'] ?? '') as String;
        final notifId  = callId.isNotEmpty ? callId.hashCode : DateTime.now().millisecondsSinceEpoch ~/ 1000;

        await _fln.show(
          notifId,
          '$caller is ${callType == 'video' ? 'video ' : ''}calling you',
          'Tap to answer',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'call_channel_v2', 'Calls',
              importance: Importance.max,
              priority: Priority.max,
              fullScreenIntent: true,
              category: AndroidNotificationCategory.call,
              ongoing: true,
              visibility: NotificationVisibility.public,
            ),
            iOS: DarwinNotificationDetails(presentSound: true),
          ),
          payload: route,
        );
        return;
      }

      // No popup for messages in foreground
      onForegroundMessage?.call(m);
    });

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    final r0 = initial?.data['route'];
    if (r0 != null && r0.isNotEmpty) {
      stopRingtone();
      Future.microtask(() => onOpenRoute?.call(r0));
    }

    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      stopRingtone();
      final route = m.data['route'];
      if (route != null && route.isNotEmpty) onOpenRoute?.call(route);
    });
  }

  static Future<String?> getToken() => FirebaseMessaging.instance.getToken();

  /// Foreground looping ringtone from assets/ringtone.mp3
  static Future<void> startRingtone({Duration timeout = const Duration(seconds: 45)}) async {
    await stopRingtone();
    try {
      await _ringPlayer.stop();
      await _ringPlayer.setReleaseMode(ReleaseMode.loop);
      await _ringPlayer.play(AssetSource('ringtone.mp3'), volume: 1.0); // pubspec: assets/ringtone.mp3
      _ringTimer = Timer(timeout, stopRingtone);
    } catch (_) {}
  }

  static Future<void> stopRingtone() async {
    _ringTimer?.cancel();
    _ringTimer = null;
    try { await _ringPlayer.stop(); } catch (_) {}
  }

  static Future<void> showIncomingCall({
    required String title,
    required String body,
    required String route,
  }) async {
    await startRingtone(timeout: const Duration(seconds: 45));
    await _fln.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'call_channel_v2', 'Calls',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
          ongoing: true,
          visibility: NotificationVisibility.public,
        ),
        iOS: DarwinNotificationDetails(presentSound: true),
      ),
      payload: route,
    );
  }
}
