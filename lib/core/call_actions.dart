// lib/core/call_actions.dart
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Call push helper:
/// - Builds a canonical deep link: `/incoming-call?threadId=...&callId=...&video=0|1&callerName=...`
/// - Sends a DATA-ONLY push (Edge Function 'send_push_users') with redundant fields in `data`
///   so the app can reconstruct the route even if the top-level `route` is stripped.
class CallActions {
  CallActions._();

  /// Convenience used by UI when you ALREADY created an invite row and have a concrete [callId].
  static Future<void> startCall({
    required String threadId,
    required String calleeUserId,
    required bool video,
    required String callerName,
    required String callId, // should match your call_invites.id
  }) async {
    final sb = Supabase.instance.client;
    final me = sb.auth.currentUser?.id;
    if (me == null) {
      throw Exception('Not signed in.');
    }

    final route = _buildIncomingRoute(
      threadId: threadId,
      callId: callId,
      video: video,
      callerName: callerName,
    );

    await sb.functions.invoke('send_push_users', body: {
      'userIds': [calleeUserId],         // notify only this user
      'fromUserId': me,                  // caller
      'senderName': callerName,          // mirrored at root (for legacy clients)
      'isCall': true,                    // server should send DATA-ONLY for calls
      'pruneInvalid': true,

      // Redundant: some push paths expect route at the top level
      'route': route,

      // === Everything the client needs to render the call ===
      // Put ALL fields into `data` too, so PushService can rebuild on any device.
      'data': {
        'type': 'call',
        'threadId': threadId,
        'callId': callId,
        'callType': video ? 'video' : 'audio',
        'callerName': callerName,
        'route': route,
      },
    });
  }

  /// Start a 1:1 call to a specific user, generating a new [callId]. Returns the [callId].
  static Future<String> startCallToUser({
    required String peerUserId,
    required String threadId,
    bool video = true,
    String? callerName,
  }) async {
    final sb = Supabase.instance.client;
    final me = sb.auth.currentUser?.id;
    if (me == null) {
      throw Exception('Not signed in.');
    }

    final callId = _generateCallId();
    final route = _buildIncomingRoute(
      threadId: threadId,
      callId: callId,
      video: video,
      callerName: callerName ?? '',
    );

    await sb.functions.invoke('send_push_users', body: {
      'userIds': [peerUserId],
      'fromUserId': me,
      if (callerName != null) 'senderName': callerName,
      'isCall': true,
      'pruneInvalid': true,
      'route': route, // top-level

      'data': {
        'type': 'call',
        'threadId': threadId,
        'callId': callId,
        'callType': video ? 'video' : 'audio',
        if (callerName != null) 'callerName': callerName,
        'route': route,
      },
    });

    return callId;
  }

  /// Start a call to everyone in a thread (server excludes the caller). Returns the [callId].
  static Future<String> startCallInThread({
    required String threadId,
    bool video = true,
    String? callerName,
  }) async {
    final sb = Supabase.instance.client;
    final me = sb.auth.currentUser?.id;
    if (me == null) {
      throw Exception('Not signed in.');
    }

    final callId = _generateCallId();
    final route = _buildIncomingRoute(
      threadId: threadId,
      callId: callId,
      video: video,
      callerName: callerName ?? '',
    );

    await sb.functions.invoke('send_push_users', body: {
      'threadId': threadId, // server figures recipients (excludes caller)
      'fromUserId': me,
      if (callerName != null) 'senderName': callerName,
      'isCall': true,
      'pruneInvalid': true,
      'route': route,

      'data': {
        'type': 'call',
        'threadId': threadId,
        'callId': callId,
        'callType': video ? 'video' : 'audio',
        if (callerName != null) 'callerName': callerName,
        'route': route,
      },
    });

    return callId;
  }

  /// Start a call to multiple explicit recipients. Returns the [callId].
  static Future<String> startCallToUsers({
    required List<String> userIds,
    required String threadId,
    bool video = true,
    String? callerName,
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
    final route = _buildIncomingRoute(
      threadId: threadId,
      callId: callId,
      video: video,
      callerName: callerName ?? '',
    );

    // Exclude caller if accidentally included
    final targets = userIds.where((id) => id.isNotEmpty && id != me).toList();
    if (targets.isEmpty) {
      throw Exception('No valid recipients.');
    }

    await sb.functions.invoke('send_push_users', body: {
      'userIds': targets,
      'fromUserId': me,
      if (callerName != null) 'senderName': callerName,
      'isCall': true,
      'pruneInvalid': true,
      'route': route,

      'data': {
        'type': 'call',
        'threadId': threadId,
        'callId': callId,
        'callType': video ? 'video' : 'audio',
        if (callerName != null) 'callerName': callerName,
        'route': route,
      },
    });

    return callId;
  }

  // ---------------- helpers ----------------

  /// Build the deep link that opens the **callee**’s IncomingCallScreen.
  static String _buildIncomingRoute({
    required String threadId,
    required String callId,
    required bool video,
    required String callerName,
  }) {
    // push_route_handler supports `/incoming-call`, `/call`, `/incoming_call`.
    // We standardize on `/incoming-call`.
    final params = {
      'threadId': threadId,
      'callId': callId,
      // _qBool understands 1/0 and true/false; we send 1/0 for brevity.
      'video': video ? '1' : '0',
      if (callerName.isNotEmpty) 'callerName': Uri.encodeComponent(callerName),
    };

    final qp = params.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');

    return '/incoming-call?$qp';
  }

  static String _generateCallId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = _randString(6);
    return 'call_${ts}_$rand';
    // If you persist invites in DB first, prefer using that row's id.
  }

  static String _randString(int len) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(len, (_) => chars.codeUnitAt(r.nextInt(chars.length))),
    );
  }
}
