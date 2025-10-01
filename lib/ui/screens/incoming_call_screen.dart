// lib/ui/screens/incoming_call_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_routes.dart';
import '../../core/ringtone.dart';
import '../../core/push_service.dart';
import 'call_screen.dart' show CallArgs;

class IncomingCallArgs {
  final String inviteId;   // DB row id (or your generated callId)
  final String threadId;
  final String callerName; // may be empty; we’ll resolve if so
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
  bool _accepted = false;

  String _callerLabel = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    debugPrint(
      '[IncomingCallScreen] inviteId=${widget.args.inviteId} '
          'threadId=${widget.args.threadId} video=${widget.args.video} '
          'callerName="${widget.args.callerName}"',
    );

    Ringtone.start();

    final incoming = widget.args.callerName.trim().toLowerCase();
    _callerLabel = (incoming.isEmpty ||
        incoming == 'aitalk' ||
        incoming == 'someone' ||
        incoming == 'unknown' ||
        incoming == 'null' ||
        incoming == 'undefined')
        ? ''
        : widget.args.callerName.trim();

    _listenInvite();

    if (_callerLabel.isEmpty) {
      _loadCallerName(); // resolve name from DB if missing
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      if (_chan != null) _sb.removeChannel(_chan!);
    } catch (_) {}
    if (!_accepted) {
      Ringtone.stop();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_acting) return; // don't restart sound once user acted
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      Ringtone.stop();
    } else if (state == AppLifecycleState.resumed) {
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
        debugPrint('[Incoming] invite update → $status');
        if (status == null) return;
        if (status == 'canceled' || status == 'timeout' || status == 'ended') {
          _stopAndPop();
        }
      },
    )
        .subscribe();
  }

  Future<void> _loadCallerName() async {
    try {
      final me = _sb.auth.currentUser?.id;
      if (me == null) return;

      final memRows = await _sb
          .from('thread_members')
          .select('user_id')
          .eq('thread_id', widget.args.threadId);

      final ids = (memRows as List)
          .map((r) => (r as Map)['user_id'] as String)
          .where((id) => id != me)
          .toList();

      if (ids.isEmpty) return;

      final orClause = ids.map((id) => 'id.eq.$id').join(',');
      final profs = await _sb
          .from('users')
          .select('id, display_name, email')
          .or(orClause);

      String? resolved;
      for (final p in profs as List) {
        final m = p as Map<String, dynamic>;
        final dn = (m['display_name'] as String?)?.trim();
        if (dn != null && dn.isNotEmpty) {
          resolved = dn;
          break;
        }
        final email = (m['email'] as String?) ?? '';
        if (email.isNotEmpty) {
          resolved = email.split('@').first;
          break;
        }
      }

      if (resolved != null && resolved.isNotEmpty && mounted) {
        setState(() => _callerLabel = resolved!);
      }
    } catch (_) {
      // ignore lookup errors
    }
  }

  Future<void> _accept() async {
    if (_acting) return;
    _acting = true;
    try {
      final updated = await _sb
          .from('call_invites')
          .update({'status': 'accepted'})
          .eq('id', widget.args.inviteId)
          .select('id')
          .maybeSingle();

      if (updated == null) {
        throw Exception('Invite not found: ${widget.args.inviteId}');
      }

      await PushService.startCallSession(callId: widget.args.inviteId);
      Ringtone.stop();

      if (!mounted) return;
      _accepted = true;

      final title = _callerLabel.isNotEmpty
          ? _callerLabel
          : (widget.args.video ? 'Video call' : 'Audio call');

      Navigator.pushReplacementNamed(
        context,
        AppRoutes.call,
        arguments: CallArgs(
          threadId: widget.args.threadId,
          title: title,
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
      final updated = await _sb
          .from('call_invites')
          .update({'status': 'declined'})
          .eq('id', widget.args.inviteId)
          .select('id')
          .maybeSingle();

      if (updated == null) {
        throw Exception('Invite not found: ${widget.args.inviteId}');
      }

      await PushService.endCallSession(callId: widget.args.inviteId);
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
                      _callerLabel.isNotEmpty
                          ? _callerLabel
                          : 'Incoming ${widget.args.video ? "video" : "audio"} call',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
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
