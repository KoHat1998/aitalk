// lib/core/push_notify.dart
import 'package:supabase_flutter/supabase_flutter.dart';

final _sb = Supabase.instance.client;

/// Notify everyone in a thread except me (recommended)
Future<void> notifyThread({
  required String threadId,
  required String senderUserId,
  required String previewText,
  String? senderName, // optional; the server can also look it up
}) async {
  await _sb.functions.invoke('send_push_users', body: {
    'threadId': threadId,           // server resolves members, excludes me
    'fromUserId': senderUserId,     // sender
    'preview': previewText,         // becomes notification body
    if (senderName != null) 'senderName': senderName,
    'route': '/thread/$threadId',
    'data': {'threadId': threadId},
    'pruneInvalid': true,
  });
}

/// 1:1 notify explicitly by recipient id (optional alternative)
Future<void> notifyMessage({
  required String threadId,
  required String recipientUserId,
  required String senderUserId,
  required String previewText,
  String? senderName,
}) async {
  await _sb.functions.invoke('send_push_users', body: {
    'userIds': [recipientUserId],   // recipients ONLY
    'fromUserId': senderUserId,     // sender
    'preview': previewText,
    if (senderName != null) 'senderName': senderName,
    'route': '/thread/$threadId',
    'data': {'threadId': threadId},
    'pruneInvalid': true,
  });
}
