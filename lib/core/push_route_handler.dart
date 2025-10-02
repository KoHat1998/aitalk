// lib/core/push_route_handler.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // ⬅️ new

import 'app_routes.dart';
import '../ui/screens/thread_screen.dart' show ThreadArgs;
import '../ui/screens/incoming_call_screen.dart' show IncomingCallArgs;

/// Global navigator key so push callbacks can navigate even from cold start.
final GlobalKey<NavigatorState> pushNavKey = GlobalKey<NavigatorState>();

// ---------- READY GATE / QUEUE ----------
bool _routingReady = false;
final List<String> _pendingRoutes = [];

bool _isPlaceholderName(String s) {
  final t = s.trim().toLowerCase();
  return t.isEmpty ||
      t == 'someone' ||
      t == 'aitalk' ||
      t == 'unknown' ||
      t == 'null' ||
      t == 'undefined';
}

bool _qBool(Map<String, String> q, String key, {bool def = false}) {
  final v = (q[key] ?? '').toLowerCase();
  if (v == '1' || v == 'true' || v == 'yes') return true;
  if (v == '0' || v == 'false' || v == 'no') return false;
  return def;
}

Uri _normalizeUri(String route) {
  Uri u;
  try {
    u = Uri.parse(route);
  } catch (_) {
    return Uri(path: '/');
  }
  if (u.hasScheme || u.host.isNotEmpty) {
    return Uri(path: '/${u.pathSegments.join('/')}', queryParameters: u.queryParameters);
  }
  return u;
}

/// Waits until MaterialApp has attached the Navigator (for cold-start taps).
Future<void> _withNavigator(
    FutureOr<void> Function(NavigatorState nav) fn, {
      Duration timeout = const Duration(seconds: 8), // longer wait for slow boots
      Duration pollEvery = const Duration(milliseconds: 40),
    }) async {
  final sw = Stopwatch()..start();
  while (pushNavKey.currentState == null && sw.elapsed < timeout) {
    await Future<void>.delayed(pollEvery);
  }
  final nav = pushNavKey.currentState;
  if (nav != null) await fn(nav);
}

/// Call this once your app finishes splash/auth selection.
/// Returns true if it consumed a deep-link (thread/call), so Splash must STOP normal nav.
Future<bool> markPushRoutingReady() async {
  _routingReady = true;

  // 1) Drain any route queued before we were ready
  if (_pendingRoutes.isNotEmpty) {
    final routes = List<String>.from(_pendingRoutes);
    _pendingRoutes.clear();
    for (final r in routes) {
      _go(r);
    }
    return true;
  }

  // 2) Nothing queued? Also check FCM "initial message" (cold start tap)
  try {
    final im = await FirebaseMessaging.instance.getInitialMessage();
    if (im != null) {
      final data = im.data;
      // Prefer explicit route if provided
      String route = (data['route'] as String?)?.trim() ?? '';

      if (route.isEmpty) {
        // Build canonical route from message data
        final type = (data['type'] ?? '').toString();
        if (type == 'call') {
          final threadId = (data['threadId'] ?? data['thread_id'] ?? '').toString();
          final callId   = (data['callId']   ?? '').toString();
          final isVideo  = ((data['callType'] ?? 'audio').toString().toLowerCase() == 'video');
          var caller     = ((data['callerName'] ?? data['senderName'] ?? '') as String).trim();
          if (_isPlaceholderName(caller)) caller = '';

          final qp = <String, String>{
            if (threadId.isNotEmpty) 'threadId': threadId,
            if (callId.isNotEmpty)   'callId': callId,
            'video': isVideo ? '1' : '0',
            if (caller.isNotEmpty)   'callerName': caller,
          };
          route = Uri(path: '/incoming-call', queryParameters: qp).toString();
        } else {
          final threadId = (data['threadId'] ?? data['thread_id'] ?? '').toString();
          if (threadId.isNotEmpty) {
            route = '/thread/$threadId';
          }
        }
      }

      if (route.isNotEmpty) {
        _go(route);
        return true;
      }
    }
  } catch (_) {
    // ignore – we still fall back to normal nav
  }

  return false;
}

void handlePushRoute(String route) {
  if (route.isEmpty) return;

  // If app hasn't declared itself "ready" yet, queue the deep link.
  if (!_routingReady) {
    _pendingRoutes.add(route);
    return;
  }
  _go(route);
}

void _go(String route) {
  final uri = _normalizeUri(route);
  final path = uri.path;

  // ---------- Incoming call deep-links ----------
  if (path == '/incoming-call' || path == '/call' || path == '/incoming_call') {
    final q = uri.queryParameters;
    final threadId  = q['threadId'] ?? q['thread_id'] ?? '';
    final inviteId  = q['inviteId'] ?? q['callId'] ?? '';
    final isVideo   = _qBool(q, 'video', def: false);

    var caller = (q['callerName'] ?? q['senderName'] ?? '').trim();
    if (_isPlaceholderName(caller)) caller = ''; // let screen resolve from DB

    _withNavigator((nav) {
      final args = IncomingCallArgs(
        inviteId: inviteId,
        threadId: threadId,
        video: isVideo,
        callerName: caller,
      );
      // Always make it the root on deep-link so Splash/Shell don't override
      nav.pushNamedAndRemoveUntil(AppRoutes.incomingCall, (r) => false, arguments: args);
    });
    return;
  }

  // ---------- Chat deep-links ----------
  if (path.startsWith('/thread')) {
    String id = '';
    if (uri.pathSegments.length >= 2) {
      id = uri.pathSegments[1];
    } else {
      id = uri.queryParameters['id'] ??
          uri.queryParameters['threadId'] ??
          uri.queryParameters['thread_id'] ??
          '';
    }
    if (id.isEmpty) return;

    final title   = uri.queryParameters['title'] ?? 'Chat';
    final isGroup = _qBool(uri.queryParameters, 'isGroup', def: false);

    _withNavigator((nav) {
      final args = ThreadArgs(threadId: id, title: title, isGroup: isGroup);
      // Make the thread screen the root so it doesn't get replaced by Shell
      nav.pushNamedAndRemoveUntil(AppRoutes.thread, (r) => false, arguments: args);
    });
    return;
  }
}
