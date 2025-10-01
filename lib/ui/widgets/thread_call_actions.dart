import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/call_actions.dart';

/// App bar actions for starting audio/video calls from a thread.
/// Works for both 1:1 (peerUserId != null) and group threads.
class ThreadCallActions extends StatelessWidget {
  final String threadId;
  final bool isGroup;
  final String? peerUserId;
  final String? title; // optional, for your own analytics/logging

  const ThreadCallActions({
    super.key,
    required this.threadId,
    required this.isGroup,
    this.peerUserId,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Audio call',
          icon: const Icon(Icons.call),
          onPressed: () => _start(context, video: false),
        ),
        IconButton(
          tooltip: 'Video call',
          icon: const Icon(Icons.videocam),
          onPressed: () => _start(context, video: true),
        ),
      ],
    );
  }

  Future<void> _start(BuildContext context, {required bool video}) async {
    final sb = Supabase.instance.client;
    if (sb.auth.currentUser == null) {
      _snack(context, 'Please sign in first.');
      return;
    }

    // Small progress dialog while we trigger the push
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    String callId = '';
    try {
      if (!isGroup && (peerUserId ?? '').isNotEmpty) {
        callId = await CallActions.startCallToUser(
          peerUserId: peerUserId!,
          threadId: threadId,
          video: video,
        );
      } else {
        callId = await CallActions.startCallInThread(
          threadId: threadId,
          video: video,
        );
      }
      // Close the spinner
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();

      // Navigate to your existing Outgoing Call screen.
      // NOTE: Make sure your router has a '/outgoing-call' route
      // that reads these arguments.
      // If your route name is different, change it here.
      Navigator.of(context).pushNamed(
        '/outgoing-call',
        arguments: {
          'threadId': threadId,
          'callId': callId,
          'video': video,
          'peerUserId': peerUserId,
          'title': title,
        },
      );

      // Optional: a small toast/snack
      _snack(context, video ? 'Starting video call…' : 'Starting audio call…');
    } catch (e) {
      // Close the spinner if still open
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      _snack(context, 'Could not start call: $e');
    }
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
