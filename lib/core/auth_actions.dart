// lib/core/auth_actions.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'push_token.dart';

class AuthActions {
  /// Call this from your Logout button.
  static Future<void> signOutRotateToken(BuildContext context) async {
    try {
      // 1) rotate token first (delete DB row + device token)
      await PushToken.rotateOnLogout();
    } catch (_) {}
    try {
      // 2) sign out session
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    if (context.mounted) {
      // 3) send user to sign-in screen (adjust route if different)
      Navigator.of(context).pushNamedAndRemoveUntil('/sign-in', (r) => false);
    }
  }
}
