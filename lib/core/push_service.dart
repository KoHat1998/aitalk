// lib/core/push_service.dart
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:audioplayers/audioplayers.dart';

/// ---------------- utils ----------------
String _pickString(dynamic v) => v is String ? v.trim() : '';

bool _isPlaceholderName(String s) {
  final t = s.trim().toLowerCase();
  return t.isEmpty ||
      t == 'someone' ||
      t == 'aitalk' ||
      t == 'unknown' ||
      t == 'null' ||
      t == 'undefined';
}

String _bestCallerName(Map<String, dynamic> data) {
  // Prefer explicit fields in data
  final d1 = _pickString(data['callerName'] ?? data['senderName']);
  if (!_isPlaceholderName(d1)) return d1;

  // Fallback to deep-link query param
  final route = _pickString(data['route']);
  if (route.isNotEmpty) {
    try {
      final qp = Uri.parse(route).queryParameters['callerName'] ?? '';
      if (!_isPlaceholderName(qp)) return qp.trim();
    } catch (_) {}
  }
  return ''; // Force screen to resolve from DB
}

/// Build canonical deep-link for incoming call. Include callerName only if real.
String _ensureCallRoute(Map<String, dynamic> data) {
  final String threadId = _pickString(data['threadId'] ?? data['thread_id']);
  final String callId   = _pickString(data['callId']);
  final String callType = _pickString(data['callType']).isEmpty ? 'audio' : _pickString(data['callType']);
  final bool isVideo    = callType.toLowerCase() == 'video';
  final String caller   = _bestCallerName(data); // may be ''

  final qp = <String, String>{
    if (threadId.isNotEmpty) 'threadId': threadId,
    if (callId.isNotEmpty)   'callId': callId,
    'video': isVideo ? '1' : '0',
    if (caller.isNotEmpty)   'callerName': caller,
  };
  return Uri(path: '/incoming-call', queryParameters: qp).toString();
}

/// Build canonical deep-link for a message/thread tap (used for cold start).
String _ensureMessageRoute(Map<String, dynamic> data) {
  // accept threadId from either top-level or snake_case
  String threadId = _pickString(data['threadId'] ?? data['thread_id']);

  // also accept threadId inside a nested "data" map (defensive)
  if (threadId.isEmpty && data['data'] is Map) {
    final inner = (data['data'] as Map);
    threadId = _pickString(inner['threadId'] ?? inner['thread_id']);
  }

  if (threadId.isEmpty) return '';
  return Uri(path: '/thread/$threadId').toString();
}

/// =================== TOP-LEVEL CALLBACKS (REQUIRED) ===================

@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage m) async {
  try { await Firebase.initializeApp(); } catch (_) {}
  if ((_pickString(m.data['type'])) != 'call') return;

  final String callId = _pickString(m.data['callId']);
  if (callId.isNotEmpty && PushService._shownCallIds.contains(callId)) return;

  final String callType = _pickString(m.data['callType']).isEmpty ? 'audio' : _pickString(m.data['callType']);
  final String caller   = _bestCallerName(m.data);
  final String route    = _pickString(m.data['route']).isNotEmpty
      ? _pickString(m.data['route'])
      : _ensureCallRoute(m.data);

  final int notifId = callId.isNotEmpty
      ? callId.hashCode
      : DateTime.now().millisecondsSinceEpoch ~/ 1000;

  final fln = FlutterLocalNotificationsPlugin();
  final androidImpl =
  fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  // Make sure channels exist even in bg isolate
  await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
    'default_channel', 'General',
    description: 'Default chat notifications',
    importance: Importance.defaultImportance,
  ));
  await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
    'call_channel_v2', 'Calls',
    description: 'Incoming calls',
    importance: Importance.max,
    sound: RawResourceAndroidNotificationSound('ringtone'), // android/app/src/main/res/raw/ringtone.mp3
    playSound: true,
  ));

  // ✅ fixed string (balanced quotes + space)
  final String title = caller.isEmpty
      ? 'Incoming $callType call'
      : '$caller is ${callType == "video" ? "video " : ""}calling you';

  await fln.show(
    notifId,
    title,
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

  PushService._activeNotifId = notifId;
  if (callId.isNotEmpty) PushService._shownCallIds.add(callId);
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse resp) {
  final payload = resp.payload;
  if (payload != null && payload.isNotEmpty) {
    PushService.enqueueRoute(payload);
  }
}

/// ============================== SERVICE ==============================

class PushService {
  static final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();
  static final AudioPlayer _ringPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.loop);
  static Timer? _ringTimer;

  // Call state & de-dupe
  static bool _callActive = false;
  static final Set<String> _shownCallIds = <String>{};
  static int? _activeNotifId;

  // Route handoff
  static void Function(String route)? _onOpenRoute;
  static String? _queuedRoute;

  static void enqueueRoute(String route) {
    _queuedRoute = route;
    final h = _onOpenRoute;
    if (h != null) {
      Future.microtask(() {
        final r = _queuedRoute;
        _queuedRoute = null;
        if (r != null && r.isNotEmpty) h(r);
      });
    }
  }

  static Future<void> init({
    void Function(String route)? onOpenRoute,
    void Function(RemoteMessage m)? onForegroundMessage,
  }) async {
    await Firebase.initializeApp();
    _onOpenRoute = onOpenRoute;

    // Flush any queued route that arrived before init completed
    final queued = _queuedRoute;
    _queuedRoute = null;
    if (queued != null && queued.isNotEmpty) {
      Future.microtask(() => _onOpenRoute?.call(queued));
    }

    // Ringtone audio context
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
      onDidReceiveNotificationResponse: (resp) async {
        await stopRingtone();
        if (_activeNotifId != null) {
          try { await _fln.cancel(_activeNotifId!); } catch (_) {}
          _activeNotifId = null;
        }
        final route = resp.payload;
        if (route != null && route.isNotEmpty) onOpenRoute?.call(route);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    // Cold-start tap from a *local* notification (calls)
    final launch = await _fln.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final payload = launch!.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        await stopRingtone();
        enqueueRoute(payload);
      }
    }

    // Ensure channels exist for message notifications shown by FCM
    final androidImpl =
    _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
      'default_channel', 'General',
      description: 'Default chat notifications',
      importance: Importance.defaultImportance,
    ));
    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
      'call_channel_v2', 'Calls',
      description: 'Incoming calls',
      importance: Importance.max,
      sound: RawResourceAndroidNotificationSound('ringtone'),
      playSound: true,
    ));

    // App in foreground: let the app decide (you already ignore system banner)
    FirebaseMessaging.onMessage.listen((m) async {
      final myId = Supabase.instance.client.auth.currentUser?.id;
      final senderId = m.data['senderId'];
      if (myId != null && senderId != null && senderId == myId) return;

      if ((_pickString(m.data['type'])) == 'call') {
        final String callId = _pickString(m.data['callId']);
        if (_callActive) return;
        if (callId.isNotEmpty && _shownCallIds.contains(callId)) return;

        await startRingtone(timeout: const Duration(seconds: 45));

        final String callType = _pickString(m.data['callType']).isEmpty ? 'audio' : _pickString(m.data['callType']);
        final String caller   = _bestCallerName(m.data);
        final String route    = _pickString(m.data['route']).isNotEmpty
            ? _pickString(m.data['route'])
            : _ensureCallRoute(m.data);

        final int notifId = callId.isNotEmpty
            ? callId.hashCode
            : DateTime.now().millisecondsSinceEpoch ~/ 1000;

        _activeNotifId = notifId;
        if (callId.isNotEmpty) _shownCallIds.add(callId);

        // ✅ fixed string (balanced quotes + space)
        final String title = caller.isEmpty
            ? 'Incoming $callType call'
            : '$caller is ${callType == "video" ? "video " : ""}calling you';

        await _fln.show(
          notifId,
          title,
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

      onForegroundMessage?.call(m);
    });

    // FCM-originated deep links (cold start for *messages* and data-tap)
    final im = await FirebaseMessaging.instance.getInitialMessage();
    if (im != null) {
      final data = im.data;
      String route = _pickString(data['route']);

      if (route.isEmpty) {
        final isCall = _pickString(data['type']) == 'call';
        route = isCall ? _ensureCallRoute(data) : _ensureMessageRoute(data);
      }

      if (route.isNotEmpty) {
        await stopRingtone();
        enqueueRoute(route);
      }
    }

    // App was in background; user tapped the system notification
    FirebaseMessaging.onMessageOpenedApp.listen((m) async {
      final data = m.data;
      String route = _pickString(data['route']);

      if (route.isEmpty) {
        final isCall = _pickString(data['type']) == 'call';
        route = isCall ? _ensureCallRoute(data) : _ensureMessageRoute(data);
      }

      if (route.isNotEmpty) {
        await stopRingtone();
        enqueueRoute(route);
      }
    });
  }

  static Future<String?> getToken() => FirebaseMessaging.instance.getToken();

  /// ====== Call session helpers ======
  static Future<void> startCallSession({String? callId}) async {
    _callActive = true;
    await stopRingtone();
    if (_activeNotifId != null) {
      try { await _fln.cancel(_activeNotifId!); } catch (_) {}
      _activeNotifId = null;
    }
    if (callId != null && callId.isNotEmpty) {
      _shownCallIds.add(callId);
    }
  }

  static Future<void> endCallSession({String? callId}) async {
    _callActive = false;
    await stopRingtone();
    if (_activeNotifId != null) {
      try { await _fln.cancel(_activeNotifId!); } catch (_) {}
      _activeNotifId = null;
    }
    if (callId != null && callId.isNotEmpty) {
      _shownCallIds.remove(callId);
    } else {
      _shownCallIds.clear();
    }
  }

  static Future<void> cancelIncomingCall(String callId) async {
    final id = callId.isNotEmpty ? callId.hashCode : _activeNotifId;
    if (id != null) {
      try { await _fln.cancel(id); } catch (_) {}
    }
    await stopRingtone();
  }

  /// ====== Ringtone helpers ======
  static Future<void> startRingtone({Duration timeout = const Duration(seconds: 45)}) async {
    await stopRingtone();
    try {
      await _ringPlayer.stop();
      await _ringPlayer.setReleaseMode(ReleaseMode.loop);
      await _ringPlayer.play(AssetSource('ringtone.mp3'), volume: 1.0);
      _ringTimer = Timer(timeout, stopRingtone);
    } catch (_) {}
  }

  static Future<void> stopRingtone() async {
    _ringTimer?.cancel();
    _ringTimer = null;
    try { await _ringPlayer.stop(); } catch (_) {}
  }

  // Manual trigger (optional)
  static Future<void> showIncomingCall({
    required String title,
    required String body,
    required String route,
    String? callId,
    Duration ringFor = const Duration(seconds: 45),
  }) async {
    if (_callActive) return;
    if (callId != null && callId.isNotEmpty && _shownCallIds.contains(callId)) return;

    await startRingtone(timeout: ringFor);

    final int notifId = (callId != null && callId.isNotEmpty)
        ? callId.hashCode
        : DateTime.now().millisecondsSinceEpoch ~/ 1000;

    _activeNotifId = notifId;
    if (callId != null && callId.isNotEmpty) _shownCallIds.add(callId);

    await _fln.show(
      notifId,
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
