// lib/core/call_actions.dart
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';

class CallActions {
  CallActions._();

  /// Start a 1:1 call to a specific user.
  /// Returns the generated callId (use it to open your OutgoingCallScreen, if needed).
  static Future<String> startCallToUser({
    required String peerUserId,
    required String threadId,
    bool video = true,
  }) async {
    final sb = Supabase.instance.client;
    final me = sb.auth.currentUser?.id;
    if (me == null) {
      throw Exception('Not signed in.');
    }

    final callId = _generateCallId();
    final route = '/call?threadId=$threadId&callId=$callId';

    await sb.functions.invoke('send_push_users', body: {
      'userIds': [peerUserId],     // notify this user only
      'fromUserId': me,            // caller
      'isCall': true,              // server sends DATA-ONLY for calls
      'data': {
        'callType': video ? 'video' : 'audio',
        'callId'  : callId,
      },
      'route': route,              // app opens this deep link on tap
      'pruneInvalid': true,        // remove dead tokens
    });

    return callId;
  }

  /// Start a call to everyone in a thread (server excludes the caller).
  /// Works for 1:1 threads as well.
  static Future<String> startCallInThread({
    required String threadId,
    bool video = true,
  }) async {
    final sb = Supabase.instance.client;
    final me = sb.auth.currentUser?.id;
    if (me == null) {
      throw Exception('Not signed in.');
    }

    final callId = _generateCallId();
    final route = '/call?threadId=$threadId&callId=$callId';

    await sb.functions.invoke('send_push_users', body: {
      'threadId': threadId,        // server resolves recipients & excludes me
      'fromUserId': me,
      'isCall': true,
      'data': {
        'callType': video ? 'video' : 'audio',
        'callId'  : callId,
      },
      'route': route,
      'pruneInvalid': true,
    });

    return callId;
  }

  /// Start a call to multiple explicit recipients (e.g., small group).
  static Future<String> startCallToUsers({
    required List<String> userIds,
    required String threadId,
    bool video = true,
  }) async {
    if (userIds.isEmpty) {
      throw Exception('userIds is empty.');
    }
    final sb = Supabase.instance.client;
    final me = sb.auth.currentUser?.id;
    if (me == null) {
      throw Exception('Not signed in.');
    }

    final callId = _generateCallId();
    final route = '/call?threadId=$threadId&callId=$callId';

    // Exclude caller if mistakenly included
    final targets = userIds.where((id) => id.isNotEmpty && id != me).toList();
    if (targets.isEmpty) {
      throw Exception('No valid recipients.');
    }

    await sb.functions.invoke('send_push_users', body: {
      'userIds': targets,
      'fromUserId': me,
      'isCall': true,
      'data': {
        'callType': video ? 'video' : 'audio',
        'callId'  : callId,
      },
      'route': route,
      'pruneInvalid': true,
    });

    return callId;
  }

  // ---- helpers ----
  static String _generateCallId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = _randString(6);
    return 'call_${ts}_$rand';
    // Treat this as your inviteId too, for consistency with your screens.
  }

  static String _randString(int len) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(len, (_) => chars.codeUnitAt(r.nextInt(chars.length))),
    );
  }
}
