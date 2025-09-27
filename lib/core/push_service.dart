// lib/core/push_service.dart
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage message) async {
  // If heavy work needed: await Firebase.initializeApp();
}

class PushService {
  static final _fln = FlutterLocalNotificationsPlugin();

  static Future<void> init({
    void Function(String route)? onOpenRoute,
  }) async {
    await Firebase.initializeApp();

    // iOS + Android 13+
    await FirebaseMessaging.instance.requestPermission(
      alert: true, badge: true, sound: true,
    );

    // Ensure Android channels exist BEFORE any push arrives
    await _ensureAndroidChannels();

    FirebaseMessaging.onBackgroundMessage(_bgHandler);

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _fln.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        final route = resp.payload;
        if (route != null && route.isNotEmpty) onOpenRoute?.call(route);
      },
    );

    // Foreground → show local notif, but never for my own messages
    FirebaseMessaging.onMessage.listen((m) async {
      final myId = Supabase.instance.client.auth.currentUser?.id;
      final senderId = m.data['senderId'];
      if (myId != null && senderId != null && senderId == myId) return;

      final n = m.notification;
      await _fln.show(
        n.hashCode,
        n?.title,               // title comes from server (sender name)
        n?.body,                // body = preview
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'default_channel', 'General',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: m.data['route'] ?? '',
      );
    });

    // App opened from terminated via push tap
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    final r0 = initial?.data['route'];
    if (r0 != null && r0.isNotEmpty) {
      Future.microtask(() => onOpenRoute?.call(r0));
    }

    // App opened from background via push tap
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      final route = m.data['route'];
      if (route != null && route.isNotEmpty) onOpenRoute?.call(route);
    });
  }

  static Future<void> _ensureAndroidChannels() async {
    final android = _fln
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      'default_channel', 'General',
      description: 'Default chat notifications',
      importance: Importance.defaultImportance,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      'call_channel', 'Calls',
      description: 'Incoming calls',
      importance: Importance.max,
    ));
  }

  static Future<String?> getToken() => FirebaseMessaging.instance.getToken();

  static Future<void> showIncomingCall({
    required String title,
    required String body,
    required String route,
  }) async {
    await _fln.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title, body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'call_channel', 'Calls',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
          ongoing: true,
          visibility: NotificationVisibility.public,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: route,
    );
  }
}
