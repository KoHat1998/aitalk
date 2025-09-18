import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_routes.dart';
// We navigate via the ringing flow, not directly to CallScreen.
import 'outgoing_call_screen.dart' show OutgoingCallArgs;

class ThreadArgs {
  final String threadId;
  final String title;
  final bool isGroup;
  const ThreadArgs({
    required this.threadId,
    required this.title,
    this.isGroup = false,
  });
}

class ThreadScreen extends StatefulWidget {
  final ThreadArgs args;
  const ThreadScreen({super.key, required this.args});

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final _sb = Supabase.instance.client;

  late final String _tid;
  late final String _title;

  final _composer = TextEditingController();
  final _scroll = ScrollController();

  RealtimeChannel? _chan;           // messages realtime
  RealtimeChannel? _hidesChan;      // per-user hides realtime
  bool _loading = true;

  // All messages (ordered asc)
  final List<Map<String, dynamic>> _messages = [];
  // Per-user hidden message IDs (Delete for me)
  final Set<String> _hidden = {};

  String? get _myId => _sb.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _tid = widget.args.threadId;
    _title = widget.args.title;
    _load();
    _subscribeMessages();
    _subscribeMyHides();
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    if (_chan != null) _sb.removeChannel(_chan!);
    if (_hidesChan != null) _sb.removeChannel(_hidesChan!);
    super.dispose();
  }

  // ---------- Data loading ----------

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // 1) Load messages (include deleted fields)
      final rows = await _sb
          .from('messages')
          .select('id, sender_id, kind, body, created_at, deleted_at, deleted_by')
          .eq('thread_id', _tid)
          .order('created_at', ascending: true);

      _messages
        ..clear()
        ..addAll((rows as List).cast<Map<String, dynamic>>());

      // 2) Load per-user hides for these messages
      await _loadMyHidesFor(_messages.map((m) => m['id'] as String).toList());

      if (mounted) setState(() => _loading = false);
      _scrollToBottomSoon();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Failed to load messages: $e');
    }
  }

  Future<void> _loadMyHidesFor(List<String> ids) async {
    _hidden.clear();
    if (ids.isEmpty) return;
    try {
      // .or("message_id.eq.id1,message_id.eq.id2,...")
      final res = await _sb
          .from('message_hides')
          .select('message_id')
          .or(ids.map((id) => 'message_id.eq.$id').join(','));
      for (final r in res as List) {
        final mid = r['message_id'] as String?;
        if (mid != null) _hidden.add(mid);
      }
    } catch (_) {
      // Non-fatal; just means hides won't filter this pass
    }
  }

  // ---------- Realtime ----------

  void _subscribeMessages() {
    _chan = _sb.channel('realtime:messages:$_tid');

    // INSERTS (new messages)
    _chan!
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'thread_id',
        value: _tid,
      ),
      callback: (payload) {
        final rec = payload.newRecord;
        if (rec == null) return;
        final m = Map<String, dynamic>.from(rec);
        _messages.add(m);
        if (mounted) setState(() {});
        _scrollToBottomSoon();
      },
    )
    // UPDATES (soft delete / edits)
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'thread_id',
        value: _tid,
      ),
      callback: (payload) {
        final rec = payload.newRecord;
        if (rec == null) return;
        final id = rec['id'];
        final idx = _messages.indexWhere((m) => m['id'] == id);
        if (idx != -1) {
          _messages[idx] = Map<String, dynamic>.from(rec);
          if (mounted) setState(() {});
        }
      },
    )
        .subscribe();
  }

  // Realtime for "delete for me" performed on another device of this same user
  void _subscribeMyHides() {
    final me = _myId;
    if (me == null) return;

    _hidesChan = _sb.channel('realtime:message_hides:$me');

    _hidesChan!
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'message_hides',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: me,
      ),
      callback: (payload) {
        final rec = payload.newRecord;
        if (rec == null) return;
        final mid = rec['message_id'] as String?;
        if (mid == null) return;

        // Only hide if that message belongs to this thread
        if (_messages.any((m) => m['id'] == mid)) {
          _hidden.add(mid);
          if (mounted) setState(() {});
        }
      },
    )
        .subscribe();
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ---------- Sending ----------

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    setState(() {}); // briefly disables the send button via rebuild
    _composer.clear();

    final me = _myId;
    if (me == null) {
      _snack('Not signed in');
      return;
    }

    try {
      await _sb.from('messages').insert({
        'thread_id': _tid,
        'sender_id': me,
        'kind': 'text',
        'body': text,
      });
      // Realtime insert will append and scroll
    } catch (e) {
      _snack('Send failed: $e');
    }
  }

  // ---------- Delete actions ----------

  Future<void> _deleteForMe(String messageId) async {
    try {
      await _sb.from('message_hides').insert({'message_id': messageId});
      _hidden.add(messageId); // hide locally immediately
      if (mounted) setState(() {});
    } on PostgrestException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Delete failed: $e');
    }
  }

  Future<void> _deleteForEveryone(Map<String, dynamic> m) async {
    final me = _myId;
    if (me == null) {
      _snack('Not signed in');
      return;
    }
    final id = m['id'] as String;

    try {
      // All time limits / ownership checks are enforced in SQL.
      await _sb.rpc('unsend_message', params: {'p_id': id});

      // Optimistic local change; backend will also push a realtime UPDATE.
      final nowIso = DateTime.now().toUtc().toIso8601String();
      m['deleted_at'] = nowIso;
      m['deleted_by'] = me;
      m['body'] = null;
      if (mounted) setState(() {});
    } on PostgrestException catch (e) {
      _snack(e.message); // e.g., "You can only unsend within 2 minutes"
    } catch (e) {
      _snack('Delete failed: $e');
    }
  }

  void _showMessageActions(Map<String, dynamic> m) {
    final me = _myId;
    final isMine = m['sender_id'] == me;
    final alreadyDeleted = m['deleted_at'] != null || (m['kind'] == 'deleted');

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_off),
              title: const Text('Delete for me'),
              onTap: () {
                Navigator.pop(context);
                _deleteForMe(m['id'] as String);
              },
            ),
            if (isMine && !alreadyDeleted)
              ListTile(
                leading: const Icon(Icons.delete_forever),
                title: const Text('Delete for everyone'),
                subtitle: const Text('Unsend this message for all'),
                onTap: () {
                  Navigator.pop(context);
                  _deleteForEveryone(m);
                },
              ),
          ],
        ),
      ),
    );
  }

  // ---------- Calling (ringing) from a 1v1 thread ----------

  Future<void> _startCall({required bool video}) async {
    final me = _myId;
    if (me == null) {
      _snack('Not signed in');
      return;
    }

    if (widget.args.isGroup) {
      _snack('Group calls are not available yet');
      return;
    }

    try {
      // find the other participant in this 1v1
      final memRows =
      await _sb.from('thread_members').select('user_id').eq('thread_id', _tid);

      final others = (memRows as List)
          .map((m) => (m as Map)['user_id'] as String)
          .where((id) => id != me)
          .toList();

      if (others.length != 1) {
        _snack('Could not identify the other participant');
        return;
      }
      final calleeId = others.first;

      // insert invite with the requested kind
      final inserted = await _sb
          .from('call_invites')
          .insert({
        'thread_id': _tid,
        'caller_id': me,
        'callee_id': calleeId,
        'kind': video ? 'video' : 'audio',
      })
          .select('id')
          .single();

      final inviteId = inserted['id'] as String;

      if (!mounted) return;
      Navigator.pushNamed(
        context,
        AppRoutes.outgoingCall,
        arguments: OutgoingCallArgs(
          inviteId: inviteId,
          threadId: _tid,
          calleeName: _title,
          video: video,
        ),
      );
    } on PostgrestException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Could not start call: $e');
    }
  }

  void _openCallSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.call),
              title: const Text('Audio call'),
              onTap: () {
                Navigator.pop(context);
                _startCall(video: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Video call'),
              onTap: () {
                Navigator.pop(context);
                _startCall(video: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------- UI ----------

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    // Filter with per-user hides
    final visible = _messages.where((m) => !_hidden.contains(m['id'])).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: 'Call',
            icon: const Icon(Icons.call_outlined), // audio-first affordance
            onPressed: _openCallSheet,             // choose Audio/Video
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final m = visible[i];
                final isMe = m['sender_id'] == _myId;
                final deleted =
                    m['deleted_at'] != null || (m['kind'] == 'deleted');
                final body = deleted
                    ? 'Message deleted'
                    : (m['body'] as String?) ?? '';

                final ts = DateTime.tryParse(m['created_at'] ?? '') ??
                    DateTime.now();

                return Align(
                  alignment:
                  isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Card(
                      color: isMe
                          ? Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          : null,
                      margin: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 6),
                      child: InkWell(
                        onLongPress: () => _showMessageActions(m),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                body,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontStyle: deleted
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                  color:
                                  deleted ? Colors.grey.shade600 : null,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                timeOfDay(ts),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      minLines: 1,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: 'Type your message…',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String timeOfDay(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}
