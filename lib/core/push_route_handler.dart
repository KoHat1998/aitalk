// lib/core/push_route_handler.dart
import 'package:flutter/material.dart';

import 'app_routes.dart'; // for AppRoutes.thread / AppRoutes.incomingCall
import '../ui/screens/thread_screen.dart'; // for ThreadArgs

/// Global navigator key so push callbacks can navigate even from cold start.
final GlobalKey<NavigatorState> pushNavKey = GlobalKey<NavigatorState>();

/// Handles deep links coming from FCM payloads.
/// Supported:
///   - "/call?threadId=...&callId=...&video=true&callerName=Alice"
///   - "/thread/<threadId>"
/// Fallback: tries to push the raw route string.
void handlePushRoute(String route) {
  final nav = pushNavKey.currentState;
  if (nav == null) return;

  try {
    final uri = Uri.parse(route);

    // Incoming call
    if (uri.path == '/call') {
      final threadId =
          uri.queryParameters['threadId'] ?? uri.queryParameters['thread'] ?? '';
      final callId =
          uri.queryParameters['callId'] ?? uri.queryParameters['inviteId'] ?? '';
      final video =
          (uri.queryParameters['video'] ?? 'false').toLowerCase() == 'true';
      final caller =
          uri.queryParameters['callerName'] ?? uri.queryParameters['senderName'];

      nav.pushNamed(
        AppRoutes.incomingCall, // make sure your AppRoutes has this
        arguments: {
          'inviteId': callId,
          'callId': callId,
          'threadId': threadId,
          'video': video,
          if (caller != null) 'callerName': caller,
        },
      );
      return;
    }

    // Thread deep link: /thread/<id>
    if (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'thread') {
      final threadId =
      (uri.pathSegments.length >= 2) ? uri.pathSegments[1] : '';
      if (threadId.isEmpty) return;

      nav.pushNamed(
        AppRoutes.thread,
        arguments: ThreadArgs(
          threadId: threadId,
          title: 'Chat',
          isGroup: false,
          peerId: null,
        ),
      );
      return;
    }

    // Fallback: if the payload already is a named route, try it directly.
    nav.pushNamed(route);
  } catch (_) {
    // ignore parse errors
  }
}
