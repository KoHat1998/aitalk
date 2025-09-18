import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_routes.dart';
import '../../core/ringtone.dart';
import 'call_screen.dart' show CallArgs;

class OutgoingCallArgs {
  final String inviteId;
  final String threadId;
  final String calleeName;
  final bool video; // false = audio-first
  const OutgoingCallArgs({
    required this.inviteId,
    required this.threadId,
    required this.calleeName,
    this.video = false,
  });
}

class OutgoingCallScreen extends StatefulWidget {
  final OutgoingCallArgs args;
  const OutgoingCallScreen({super.key, required this.args});

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen> {
  final _sb = Supabase.instance.client;
  RealtimeChannel? _chan;
  bool _acting = false;
  bool _closed = false; // prevent double pop / double navigate

  @override
  void initState() {
    super.initState();
    // Optional: ringback while we wait
    Ringtone.start();
    _listenInvite();
  }

  @override
  void dispose() {
    if (_chan != null) _sb.removeChannel(_chan!);
    Ringtone.stop();
    super.dispose();
  }

  void _safeExit([VoidCallback? afterStop]) {
    if (_closed) return;
    _closed = true;
    Ringtone.stop();
    if (afterStop != null) afterStop();
  }

  void _listenInvite() {
    _chan = _sb
        .channel('realtime:call_invites:${widget.args.inviteId}')
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'call_invites',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: widget.args.inviteId,
      ),
      callback: (payload) {
        final status = payload.newRecord?['status'] as String?;
        if (status == null || _closed) return;

        if (status == 'accepted') {
          if (!mounted) return;
          _safeExit(() {
            Navigator.pushReplacementNamed(
              context,
              AppRoutes.call,
              arguments: CallArgs(
                threadId: widget.args.threadId,
                title: widget.args.calleeName,
                video: widget.args.video,   // audio-first if false; user can enable video in-call
                inviteId: widget.args.inviteId,
              ),
            );
          });
        } else if (status == 'declined' ||
            status == 'canceled' ||
            status == 'timeout' ||
            status == 'ended') {
          if (!mounted) return;
          _safeExit(() {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Call $status')),
            );
            Navigator.pop(context);
          });
        }
      },
    )
        .subscribe();
  }

  Future<void> _cancel() async {
    if (_acting || _closed) return;
    _acting = true;
    try {
      await _sb
          .from('call_invites')
          .update({'status': 'canceled'})
          .eq('id', widget.args.inviteId);

      if (!mounted) return;
      _safeExit(() {
        Navigator.pop(context);
      });
    } catch (e) {
      _acting = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isVideo = widget.args.video;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(isVideo ? Icons.videocam : Icons.call,
                      size: 64, color: Colors.white70),
                  const SizedBox(height: 16),
                  Text(
                    widget.args.calleeName,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isVideo ? 'Video call…' : 'Calling…',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: ElevatedButton.icon(
                    onPressed: _acting ? null : _cancel,
                    icon: const Icon(Icons.call_end),
                    label: const Text('Cancel'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: cs.error,
                      foregroundColor: cs.onError,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
