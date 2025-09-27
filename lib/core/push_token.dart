import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'push_service.dart';

class PushToken {
  /// Upsert the current device's FCM token for the signed-in user.
  static Future<void> registerForCurrentUser({String platform = 'android'}) async {
    final sb = Supabase.instance.client;
    final u = sb.auth.currentUser;
    if (u == null) return;

    final token = await PushService.getToken();
    if (token == null || token.isEmpty) return;

    await sb.from('device_tokens').upsert({
      'user_id': u.id,
      'fcm_token': token,
      'platform': platform,
    });

    // Keep token fresh if it rotates
    FirebaseMessaging.instance.onTokenRefresh.listen((t) {
      sb.from('device_tokens').upsert({
        'user_id': u.id,
        'fcm_token': t,
        'platform': platform,
      });
    });
  }
}
