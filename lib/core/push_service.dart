// lib/core/push_service.dart
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

@pragma('vm:entry-point') // required for background isolate
Future<void> _bgHandler(RemoteMessage message) async {
  // If you later need heavy work here:
  // await Firebase.initializeApp();
}

class PushService {
  static final _fln = FlutterLocalNotificationsPlugin();

  static Future<void> init({
    void Function(String route)? onOpenRoute,
  }) async {
    // Ensure Firebase is ready
    await Firebase.initializeApp();

    // Android 13+ runtime permission prompt
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Background handler
    FirebaseMessaging.onBackgroundMessage(_bgHandler);

    // Local notifications (to show while app is foreground)
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

    // Foreground: show a local notification
    FirebaseMessaging.onMessage.listen((m) async {
      final n = m.notification;
      await _fln.show(
        n.hashCode,
        n?.title,
        n?.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'default_channel',
            'General',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: m.data['route'] ?? '',
      );
    });

    // App opened from terminated via tap
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    final r0 = initial?.data['route'];
    if (r0 != null && r0.isNotEmpty) {
      Future.microtask(() => onOpenRoute?.call(r0));
    }

    // App opened from background via tap
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      final route = m.data['route'];
      if (route != null && route.isNotEmpty) onOpenRoute?.call(route);
    });
  }

  static Future<String?> getToken() => FirebaseMessaging.instance.getToken();

  // Optional helper to show an incoming-call style notification
  static Future<void> showIncomingCall({
    required String title,
    required String body,
    required String route,
  }) async {
    await _fln.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'call_channel',
          'Calls',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
          ongoing: true,
          visibility: NotificationVisibility.public,
        ),
      ),
      payload: route,
    );
  }
}
