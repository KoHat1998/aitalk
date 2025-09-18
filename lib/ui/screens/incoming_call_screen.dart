import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_routes.dart';
import '../../core/ringtone.dart';
import 'call_screen.dart' show CallArgs;

class IncomingCallArgs {
  final String inviteId;
  final String threadId;
  final String callerName;
  final bool video;
  const IncomingCallArgs({
    required this.inviteId,
    required this.threadId,
    required this.callerName,
    this.video = true,
  });
}

class IncomingCallScreen extends StatefulWidget {
  final IncomingCallArgs args;
  const IncomingCallScreen({super.key, required this.args});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with WidgetsBindingObserver {
  final _sb = Supabase.instance.client;
  RealtimeChannel? _chan;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Ringtone.start();
    _listenInvite();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_chan != null) _sb.removeChannel(_chan!);
    Ringtone.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // keep behavior predictable if app backgrounds
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      Ringtone.stop();
    } else if (state == AppLifecycleState.resumed && !_acting) {
      // resume ring when returning (still not acted upon)
      Ringtone.start();
    }
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
        if (status == null) return;

        if (status == 'canceled' ||
            status == 'timeout' ||
            status == 'ended') {
          _stopAndPop(); // caller canceled/ended
        }
      },
    )
        .subscribe();
  }

  Future<void> _accept() async {
    if (_acting) return;
    _acting = true;
    try {
      await _sb
          .from('call_invites')
          .update({'status': 'accepted'}).eq('id', widget.args.inviteId);

      Ringtone.stop();
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.call,
        arguments: CallArgs(
          threadId: widget.args.threadId,
          title: widget.args.callerName,
          video: widget.args.video,
          inviteId: widget.args.inviteId,
        ),
      );
    } catch (e) {
      _acting = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not accept: $e')));
    }
  }

  Future<void> _decline() async {
    if (_acting) return;
    _acting = true;
    try {
      await _sb
          .from('call_invites')
          .update({'status': 'declined'}).eq('id', widget.args.inviteId);
      _stopAndPop();
    } catch (e) {
      _acting = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not decline: $e')));
    }
  }

  void _stopAndPop() {
    Ringtone.stop();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.args.video ? Icons.videocam : Icons.call,
                      size: 64,
                      color: Colors.white70,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.args.callerName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Incoming ${widget.args.video ? "video" : "audio"} call…',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black54, Colors.black87],
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _acting ? null : _decline,
                          icon: const Icon(Icons.call_end),
                          label: const Text('Decline'),
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _acting ? null : _accept,
                          icon: const Icon(Icons.call),
                          label: const Text('Accept'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
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

