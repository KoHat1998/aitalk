// lib/core/push_token.dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class PushToken {
  static final _sb = Supabase.instance.client;

  /// Call after every successful login
  static Future<void> registerForCurrentUser({String platform = 'android'}) async {
    final u = _sb.auth.currentUser;
    if (u == null) return;

    // Get (or wait for) a token
    String? token = await FirebaseMessaging.instance.getToken();
    token ??= await _waitForToken();

    // Debug
    // ignore: avoid_print
    print('[PUSH] registerForCurrentUser uid=${u.id} token=$token');

    if (token == null || token.isEmpty) return;

    // Upsert token -> current user
    await _sb.from('device_tokens').upsert({
      'user_id': u.id,
      'fcm_token': token,
      'platform': platform,
    }, onConflict: 'fcm_token');

    // Keep fresh if FCM rotates it later
    FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
      final cur = _sb.auth.currentUser;
      if (cur == null) return; // user may have signed out
      // ignore: avoid_print
      print('[PUSH] onTokenRefresh uid=${cur.id} newToken=$t');
      await _sb.from('device_tokens').upsert({
        'user_id': cur.id,
        'fcm_token': t,
        'platform': platform,
      }, onConflict: 'fcm_token');
    });
  }

  /// Call **BEFORE** auth.signOut().
  /// 1) delete DB row for this token (while RLS still allows it)
  /// 2) delete the device token so next login gets a NEW token
  static Future<void> rotateOnLogout() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      // ignore: avoid_print
      print('[PUSH] rotateOnLogout currentToken=$token');
      if (token != null && token.isNotEmpty) {
        await _sb.from('device_tokens').delete().eq('fcm_token', token);
      }
    } catch (e) {
      // ignore: avoid_print
      print('[PUSH] rotateOnLogout DB delete failed: $e');
    }

    try {
      await FirebaseMessaging.instance.deleteToken();
      // ignore: avoid_print
      print('[PUSH] deleteToken() done. A new token will be issued next login.');
    } catch (e) {
      // ignore: avoid_print
      print('[PUSH] deleteToken() failed: $e');
    }
  }

  static Future<String?> _waitForToken({Duration timeout = const Duration(seconds: 10)}) async {
    final start = DateTime.now();
    String? token;
    while (token == null || token.isEmpty) {
      token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) break;
      if (DateTime.now().difference(start) > timeout) return null;
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return token;
  }
}
