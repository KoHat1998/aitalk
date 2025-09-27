// lib/ui/screens/thread_screen.dart

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_routes.dart';
import 'outgoing_call_screen.dart' show OutgoingCallArgs;
import '../widgets/chat_input_bar.dart';
import 'group_room_screen.dart';

// In-app viewers
import 'video_player_screen.dart';
import 'image_viewer_screen.dart';

class ThreadArgs {
  final String threadId;
  final String title;
  final String? peerId;
  final bool isGroup;

  const ThreadArgs({
    required this.threadId,
    required this.title,
    this.peerId,
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
  late String _title; // mutable (rename group)
  late final String? _peerId;

  final _scroll = ScrollController();

  RealtimeChannel? _chan;
  RealtimeChannel? _hidesChan;
  bool _loading = true;

  final List<Map<String, dynamic>> _messages = []; // ordered asc
  final Set<String> _hidden = {};
  DateTime? _cutoff;

  // Group members cache (id -> profile) and owner id
  final Map<String, Map<String, dynamic>> _members = {};
  String? _ownerId;

  // Per-message download state
  final Map<String, double> _dlProgress = {}; // 0..1
  final Map<String, CancelToken> _dlCancels = {};

  static const String _storageBucket = 'chat_uploads';
  bool _isPeerBlockedByMe = false;
  bool _amIBlockedByPeer = false;
  String? get _myId => _sb.auth.currentUser?.id;
  bool get _isGroup => widget.args.isGroup;

  @override
  void initState() {
    super.initState();
    _tid = widget.args.threadId;
    _title = widget.args.title;
    _peerId = widget.args.peerId;

    _loadInitialScreenData();
  }

  Future<void> _loadInitialScreenData() async{
    // Set loading true for the whole screen if needed
    if (!widget.args.isGroup && _peerId != null) {
      await _checkInitialBlockStatus(); // Wait for block status
    }
    await _load(); // Now _load() will use the correct _isPeerBlockedByMe
    _subscribeMessages();
    _subscribeMyHides();
  }

  @override
  void dispose() {
    _scroll.dispose();
    if (_chan != null) _sb.removeChannel(_chan!);
    if (_hidesChan != null) _sb.removeChannel(_hidesChan!);
    super.dispose();
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _checkInitialBlockStatus() async {
    final currentUserId = _myId;
    // Ensure peerId is available and it's not a group chat
    if (currentUserId == null || widget.args.isGroup || _peerId == null) return;

    try {
      // Check if I blocked them
      final iBlockedThemRes = await _sb
          .from('user_blocks')
          .select('id')
          .match({'blocker_user_id': currentUserId, 'blocked_user_id': _peerId!})
          .maybeSingle();

      // Check if they blocked me
      final theyBlockedMeRes = await _sb
          .from('user_blocks')
          .select('id')
          .match({'blocker_user_id': _peerId!, 'blocked_user_id': currentUserId})
          .maybeSingle();

      if (mounted) {
        setState(() {
          _isPeerBlockedByMe = iBlockedThemRes != null;
          _amIBlockedByPeer = theyBlockedMeRes != null;
        });
      }
    } catch (e) {
      print("Error checking initial block status in ThreadScreen: $e");
      // _snack("Could not verify block status.", isError: true); // Optional
    }
  }

  Future<void> _toggleBlockPeer() async {
    if (_isPeerBlockedByMe) {
      await _unblockPeer();
    } else {
      await _initiateBlockPeer();
    }
  }

  Future<void> _initiateBlockPeer() async {
    final currentUserId = _myId;
    final peerIdToBlock = _peerId; // From widget.args via initState
    final peerName = _title; // Username from widget.args

    if (currentUserId == null) {
      _snack('You need to be logged in.', isError: true);
      return;
    }
    if (peerIdToBlock == null) {
      _snack('Cannot identify the other user to block.', isError: true);
      return;
    }
    if (currentUserId == peerIdToBlock) {
      _snack('You cannot block yourself.', isError: true);
      return;
    }
    if (_isPeerBlockedByMe) {
      _snack('$peerName is already blocked by you.');
      return;
    }
    if (_amIBlockedByPeer) {
      _snack('You cannot block this user as they have blocked you.', isError: true);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Block $peerName?'),
        content: Text('You will no longer see their posts. They will not be able to call or message you. This chat will become read-only. Unblock from "Blocked Users" screen.'),
        actions: <Widget>[
          TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(dialogContext, false)),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Block'),
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _sb.from('user_blocks').insert({
        'blocker_user_id': currentUserId,
        'blocked_user_id': peerIdToBlock,
      });
      if (mounted) {
        setState(() { _isPeerBlockedByMe = true; });
        _snack('$peerName has been blocked.');
        _load();
      }
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        if (mounted) { setState(() { _isPeerBlockedByMe = true; }); }
        _snack('$peerName is already blocked.');
      } else {
        _snack('Error blocking user: ${e.message}', isError: true);
      }
    } catch (e) {
      _snack('An unexpected error occurred.', isError: true);
    }
  }

  Future<void> _unblockPeer() async {
    final currentUserId = _myId;
    final peerIdToUnblock = _peerId;
    final peerName = _title;

    if (currentUserId == null || peerIdToUnblock == null) return;
    if (!_isPeerBlockedByMe) {
      _snack("$peerName is not currently blocked by you.");
      return;
    }

    // Optional: Add confirmation dialog for unblocking too

    try {
      await _sb.from('user_blocks')
          .delete()
          .match({'blocker_user_id': currentUserId, 'blocked_user_id': peerIdToUnblock});
      if(mounted){
        setState(() { _isPeerBlockedByMe = false; });
        _snack('$peerName has been unblocked.');
        _load();
      }
    } catch (e) {
      _snack('Error unblocking user: ${e.toString()}', isError: true);
    }
  }

  // ------------------ Load ------------------
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await _loadCutoff();
      if (_isGroup) await _loadMembers();

      var q = _sb
          .from('messages')
          .select(
        'id, sender_id, kind, body, created_at, deleted_at, deleted_by, '
            'location_lat, location_lng, location_accuracy_m',
      )
          .eq('thread_id', _tid);

      if (_cutoff != null) {
        q = q.gte('created_at', _cutoff!.toUtc().toIso8601String());
      }

      final rows = await q.order('created_at', ascending: true);

      List<Map<String, dynamic>> fetchedMessages = (rows as List).cast<Map<String, dynamic>>();

      List<Map<String, dynamic>> messagesToDisplay = List.from(fetchedMessages);

      if (!_isGroup && _isPeerBlockedByMe && _peerId != null) { // Added !_isGroup check for safety
        print('DEBUG: _load - Filtering historical messages because peer $_peerId is blocked by me.');
        messagesToDisplay.removeWhere((msg) {
          final messageSenderId = msg['sender_id'] as String?;
          return messageSenderId == _peerId;
        });
      }

      _messages
        ..clear()
        ..addAll(messagesToDisplay);

      await _loadMyHidesFor(_messages.map((m) => m['id'] as String).toList());

      if (mounted) setState(() => _loading = false);
      _scrollToBottomSoon();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Failed to load messages: $e');
    }
  }

  Future<void> _loadCutoff() async {
    try {
      final me = _myId;
      if (me == null) return;
      final row = await _sb
          .from('thread_resets')
          .select('cutoff_at')
          .eq('thread_id', _tid)
          .eq('user_id', me)
          .maybeSingle();
      _cutoff = (row?['cutoff_at'] as String?) != null
          ? DateTime.tryParse(row!['cutoff_at'] as String)?.toUtc()
          : null;
    } catch (_) {
      _cutoff = null;
    }
  }

  // ----- group members / owner
  Future<void> _loadMembers() async {
    _members.clear();
    _ownerId = null;
    try {
      final t = await _sb.from('threads').select('created_by').eq('id', _tid).maybeSingle();
      _ownerId = t?['created_by'] as String?;

      final memRows =
      await _sb.from('thread_members').select('user_id').eq('thread_id', _tid);
      final ids = <String>{
        ...(memRows as List).map((m) => (m as Map)['user_id'] as String)
      };
      if (ids.isEmpty) return;

      final orClause = ids.map((id) => 'id.eq.$id').join(',');
      final profs = await _sb
          .from('users')
          .select('id, display_name, email, avatar_url')
          .or(orClause);

      for (final p in profs as List) {
        final m = Map<String, dynamic>.from(p as Map);
        _members[m['id'] as String] = m;
      }
    } catch (_) {/* ignore */}
  }

  Future<void> _loadMyHidesFor(List<String> ids) async {
    _hidden.clear();
    if (ids.isEmpty) return;
    try {
      final res = await _sb
          .from('message_hides')
          .select('message_id')
          .or(ids.map((id) => 'message_id.eq.$id').join(','));
      for (final r in res as List) {
        final mid = r['message_id'] as String?;
        if (mid != null) _hidden.add(mid);
      }
    } catch (_) {/* ignore */}
  }

  // ------------------ Realtime ------------------
  void _subscribeMessages() {
    _chan = _sb.channel('realtime:messages:$_tid')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'thread_id',
          value: _tid,
        ),
        callback: (payload) {
          final newMsgMap = payload.newRecord;
          if (newMsgMap == null || newMsgMap.isEmpty) {
            print('DEBUG: Sub - Received empty new message payload.');
            return;
          }

          print('DEBUG: Sub - Raw new message payload: $newMsgMap');
          final createdAtStr = newMsgMap['created_at'] as String?;
          if (_cutoff != null &&
              createdAtStr != null &&
              (DateTime.tryParse(createdAtStr)?.toUtc() ?? DateTime.now().toUtc())
                  .isBefore(_cutoff!)) {
            return;
          }
          final messageSenderId = newMsgMap['sender_id'] as String?;

          if (!_isGroup && _isPeerBlockedByMe && _peerId != null && messageSenderId == _peerId) { // Added !_isGroup
            print('DEBUG: Sub - Received message from blocked peer $_peerId. Hiding it. Message ID: ${newMsgMap['id']}');
            return; // << CRITICAL: Correctly returning without adding/processing
          }
          // ---- >>> FILTERING LOGIC ENDS HERE <<< ----

          // Add the message to the UI list
          // Ensure the map structure is what your UI expects
          final messageForUi = Map<String, dynamic>.from(newMsgMap);

          if (mounted) {
            setState(() {
              _messages.add(messageForUi);
              // You might need to re-sort if your list isn't always naturally ordered
              // Or if your _load() orders differently than inserts.
              // For simplicity, adding to end and relying on _scrollToBottomSoon.
            });
            _scrollToBottomSoon();
          }
        },
      )
      ..onPostgresChanges(
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
          final createdAtStr = rec['created_at'] as String?;
          if (_cutoff != null &&
              createdAtStr != null &&
              (DateTime.tryParse(createdAtStr)?.toUtc() ?? DateTime.now().toUtc())
                  .isBefore(_cutoff!)) {
            return;
          }
          final id = rec['id'];
          final idx = _messages.indexWhere((m) => m['id'] == id);
          if (idx != -1) {
            _messages[idx] = Map<String, dynamic>.from(rec);
            if (mounted) setState(() {});
          }
        },
      ).subscribe();
  }

  void _subscribeMyHides() {
    final me = _myId;
    if (me == null) return;
    _hidesChan = _sb.channel('realtime:message_hides:$me')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'message_hides',
        filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq, column: 'user_id', value: me),
        callback: (payload) {
          final mid = payload.newRecord?['message_id'] as String?;
          if (mid == null) return;
          final idx = _messages.indexWhere((m) => m['id'] == mid);
          if (idx != -1) {
            _hidden.add(mid);
            if (mounted) setState(() {});
          }
        },
      ).subscribe();
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

  // ------------------ Helpers ------------------

  bool _isUrl(String s) {
    final u = Uri.tryParse(s.trim());
    return u != null && (u.scheme == 'http' || u.scheme == 'https');
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url.trim());
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _snack('Could not open link');
    }
  }

  void _openVideo(String url, {String? title}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(url: url, title: title),
      ),
    );
  }

  void _openImage(String url, {String? title}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(url: url, title: title, heroTag: url),
      ),
    );
  }

  String _ext(String name) => p.extension(name).toLowerCase();
  bool _looksImage(String name) =>
      const ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.heic']
          .contains(_ext(name));
  bool _looksVideo(String name) =>
      const ['.mp4', '.mov', '.m4v', '.webm', '.avi', '.mkv']
          .contains(_ext(name));

  String _fileNameFromUrl(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return 'file.bin';
    var last = u.pathSegments.isNotEmpty ? u.pathSegments.last : 'file.bin';
    if (last.isEmpty) last = 'file.bin';
    return last;
  }

  // Google Maps URL -> LatLng
  LatLng? _latLngFromMapsUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;

    final q = uri.queryParameters['query'] ?? uri.queryParameters['q'];
    if (q != null) {
      final parts = q.split(',');
      if (parts.length >= 2) {
        final lat = double.tryParse(parts[0]);
        final lng = double.tryParse(parts[1]);
        if (lat != null && lng != null) return LatLng(lat, lng);
      }
    }

    // path like /@lat,lng,zoom
    final joined = uri.pathSegments.join('/');
    final atIdx = joined.indexOf('@');
    if (atIdx != -1) {
      final after = joined.substring(atIdx + 1);
      final nums = after.split(',');
      if (nums.length >= 2) {
        final lat = double.tryParse(nums[0]);
        final lng = double.tryParse(nums[1]);
        if (lat != null && lng != null) return LatLng(lat, lng);
      }
    }
    return null;
  }

  // display name helper for group
  String _displayName(String? uid) {
    if (uid == null) return 'User';
    final p = _members[uid];
    final dn = (p?['display_name'] as String?)?.trim();
    if (dn != null && dn.isNotEmpty) return dn;
    final email = (p?['email'] as String?) ?? '';
    return email.isNotEmpty ? email.split('@').first : 'User';
  }

  // ------------------ SENDING overlays ------------------

  /// Non-blocking overlay with spinner + static label ("Uploading…")
  /// Returns a closer to remove the overlay.
  VoidCallback _showBusyOverlay({required String label, bool top = false}) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        ignoring: true,
        child: Stack(children: [
          Positioned(
            left: 16,
            right: 16,
            bottom: top ? null : (80 + MediaQuery.of(context).viewInsets.bottom),
            // a little closer to the AppBar
            top: top ? (kToolbarHeight + 8) : null,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(14),
              color: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(label, style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              ),
            ),
          ),
        ]),
      ),
    );

    overlay.insert(entry);
    return () => entry.remove();
  }

  /// Updatable-label variant (kept for other cases).
  VoidCallback _showBusyOverlayVN(ValueNotifier<String> labelVN, {bool top = false}) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    void listener() => entry.markNeedsBuild();
    labelVN.addListener(listener);

    entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        ignoring: true,
        child: Stack(children: [
          Positioned(
            left: 16,
            right: 16,
            bottom: top ? null : (80 + MediaQuery.of(context).viewInsets.bottom),
            top: top ? (kToolbarHeight + 8) : null,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(14),
              color: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    ValueListenableBuilder<String>(
                      valueListenable: labelVN,
                      builder: (_, text, __) =>
                          Text(text, style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ]),
      ),
    );

    overlay.insert(entry);
    return () {
      labelVN.removeListener(listener);
      entry.remove();
    };
  }

  // ---------- Push notify helper (FIXED) ----------
  Future<void> _notifyRecipients({required String preview}) async {
    try {
      final me = _myId;
      if (me == null) return;

      // (optional) if you have my profile cached in _members, pass my name
      String? senderName;
      final mine = _members[me];
      if (mine != null) {
        senderName = (mine['display_name'] ?? mine['username'] ?? mine['full_name']) as String?;
      }

      // ✅ Let the edge function resolve recipients from threadId and exclude me.
      await _sb.functions.invoke(
        'send_push_users',
        body: {
          'threadId': _tid,              // server finds all members of this thread
          'fromUserId': me,              // sender (server excludes this id)
          'preview': preview,            // becomes notification body
          if (senderName != null) 'senderName': senderName,  // server will also look up if omitted
          'route': '/thread/$_tid',
          'data': {
            'threadId': _tid,
            'senderId': me,              // client-side guard to ignore self in foreground
          },
          'pruneInvalid': true,
        },
      );
    } catch (e) {
      // Don’t block sending if push fails
      // ignore: avoid_print
      print('send_push_users error: $e');
    }
  }

  // ------------------ Send handlers ------------------
  Future<void> _sendText(String text) async {
    if (!_isGroup && (_isPeerBlockedByMe || _amIBlockedByPeer)) {
      _snack("Cannot send message. User is blocked or has blocked you.");
      return;
    }
    final me = _myId;
    if (me == null) {
      _snack('Not signed in');
      return;
    }
    final close = _showBusyOverlay(label: 'Sending…');
    try {
      await _sb.from('messages').insert({
        'thread_id': _tid,
        'sender_id': me,
        'kind': 'text',
        'body': text.trim(),
      });

      // 🔔 Notify recipients with a short preview
      final preview = text.trim().replaceAll('\n', ' ');
      await _notifyRecipients(preview: preview.length > 80 ? '${preview.substring(0, 80)}…' : preview);
    } catch (e) {
      _snack('Send failed: $e');
    } finally {
      close();
      _scrollToBottomSoon();
    }
  }

  // ---- Upload files: fixed "Uploading…" under AppBar (no 1/N)
  Future<void> _sendFiles(List<File> files) async {
    if (!_isGroup && (_isPeerBlockedByMe || _amIBlockedByPeer)) {
      _snack("Cannot send message. User is blocked or has blocked you.");
      return;
    }
    final me = _myId;
    if (me == null) {
      _snack('Not signed in');
      return;
    }
    if (files.isEmpty) return;

    final close = _showBusyOverlay(label: 'Uploading…', top: true);

    try {
      for (int i = 0; i < files.length; i++) {
        final f = files[i];

        final bytes = await f.readAsBytes();
        final name = p.basename(f.path);
        final path = '$_tid/${DateTime.now().millisecondsSinceEpoch}_$name';

        await _sb.storage.from(_storageBucket).uploadBinary(path, bytes);
        final url = _sb.storage.from(_storageBucket).getPublicUrl(path);

        await _sb.from('messages').insert({
          'thread_id': _tid,
          'sender_id': me,
          'kind': 'text', // file messages are URL-only here
          'body': url,
        });
      }

      // 🔔 One notification for the batch
      await _notifyRecipients(preview: '📎 Attachment');
      _snack('Sent ${files.length} file${files.length == 1 ? '' : 's'}');
    } on StorageException catch (e) {
      _snack(e.message.contains('Bucket not found')
          ? 'Create a Storage bucket named "$_storageBucket" (or change the name).'
          : 'Storage error: ${e.message}');
    } catch (e) {
      _snack('File send failed: $e');
    } finally {
      close();
      _scrollToBottomSoon();
    }
  }

  Future<void> _sendLocation({
    required double lat,
    required double lng,
    double? accuracyM,
  }) async {
    if (!_isGroup && (_isPeerBlockedByMe || _amIBlockedByPeer)) {
      _snack("Cannot send message. User is blocked or has blocked you.");
      return;
    }
    final me = _myId;
    if (me == null) {
      _snack('Not signed in');
      return;
    }
    final close = _showBusyOverlay(label: 'Sending location…');
    final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    try {
      await _sb.from('messages').insert({
        'thread_id': _tid,
        'sender_id': me,
        'kind': 'location', // ensures map card shows
        'body': url,
        'location_lat': lat,
        'location_lng': lng,
        'location_accuracy_m': accuracyM,
      });

      // 🔔 Notify recipients
      await _notifyRecipients(preview: '📍 Shared a location');
    } catch (e) {
      _snack('Location send failed: $e');
    } finally {
      close();
      _scrollToBottomSoon();
    }
  }

  // ------------------ Delete ------------------
  Future<void> _deleteForMe(String messageId) async {
    try {
      await _sb.from('message_hides').insert({'message_id': messageId});
    } on PostgrestException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Delete failed: $e');
    }
    _hidden.add(messageId);
    if (mounted) setState(() {});
  }

  Future<void> _deleteForEveryone(Map<String, dynamic> m) async {
    final me = _myId;
    if (me == null) {
      _snack('Not signed in');
      return;
    }
    final id = m['id'] as String;
    try {
      await _sb.rpc('unsend_message', params: {'p_id': id});
      m['deleted_at'] = DateTime.now().toUtc().toIso8601String();
      m['deleted_by'] = me;
      m['body'] = null;
      if (mounted) setState(() {});
    } on PostgrestException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Delete failed: $e');
    }
  }

  void _showMessageActions(Map<String, dynamic> m) {
    final body = (m['body'] as String?) ?? '';
    final isLink = _isUrl(body);
    final isMine = m['sender_id'] == _myId;
    final alreadyDeleted = m['deleted_at'] != null || (m['kind'] == 'deleted');

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLink)
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Open link'),
                onTap: () {
                  Navigator.pop(context);
                  _openUrl(body);
                },
              ),
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

  // ------------------ Group management ------------------

  Future<Set<String>> _currentMemberIds() async {
    try {
      final rows = await _sb
          .from('thread_members')
          .select('user_id')
          .eq('thread_id', _tid);
      return {...(rows as List).map((r) => r['user_id'] as String)};
    } catch (_) {
      return {};
    }
  }

  Future<void> _openAddMembers() async {
    final me = _myId;
    if (me == null) {
      _snack('Not signed in');
      return;
    }

    try {
      final existing = await _currentMemberIds();

      // Load my contacts
      final contacts = await _sb
          .from('contacts')
          .select('contact_id, created_at')
          .eq('owner_id', me)
          .order('created_at', ascending: false);

      final ids = <String>[];
      final seen = <String>{};
      for (final r in contacts as List) {
        final id = (r['contact_id'] as String?) ?? '';
        if (id.isNotEmpty && !seen.contains(id) && !existing.contains(id)) {
          seen.add(id);
          ids.add(id);
        }
      }

      if (ids.isEmpty) {
        if (!mounted) return;
        _snack('No eligible contacts to add.');
        return;
      }

      final orClause = ids.map((id) => 'id.eq.$id').join(',');
      final profs = await _sb
          .from('users')
          .select('id, display_name, email, avatar_url')
          .or(orClause);

      final items = (profs as List)
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();

      final selected = <String>{};

      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => StatefulBuilder(
          builder: (context, setSheet) => AlertDialog(
            title: const Text('Add members'),
            content: SizedBox(
              width: 380,
              height: 420,
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final u = items[i];
                  final id = u['id'] as String;
                  final dn = ((u['display_name'] as String?)?.trim().isNotEmpty == true)
                      ? u['display_name'] as String
                      : ((u['email'] as String?) ?? 'User');
                  final initial = dn.isNotEmpty ? dn[0].toUpperCase() : 'U';
                  final checked = selected.contains(id);
                  return ListTile(
                    leading: CircleAvatar(child: Text(initial)),
                    title: Text(dn, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Checkbox(
                      value: checked,
                      onChanged: (_) {
                        setSheet(() {
                          if (checked) {
                            selected.remove(id);
                          } else {
                            selected.add(id);
                          }
                        });
                      },
                    ),
                    onTap: () => setSheet(() {
                      if (selected.contains(id)) {
                        selected.remove(id);
                      } else {
                        selected.add(id);
                      }
                    }),
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      );

      if (ok != true || selected.isEmpty) return;

      // Insert members (ignore existing via conflict target)
      final rows = selected.map((uid) => {
        'thread_id': _tid,
        'user_id': uid,
      }).toList();

      await _sb
          .from('thread_members')
          .upsert(rows, onConflict: 'thread_id,user_id');

      if (_isGroup) await _loadMembers();
      if (mounted) _snack('Added ${selected.length} member${selected.length == 1 ? '' : 's'}.');
    } on PostgrestException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Could not add members: $e');
    }
  }

  Future<void> _removeMember(String userId) async {
    try {
      // Prefer RPC if you added it; otherwise attempt direct delete (requires owner RLS)
      try {
        await _sb.rpc('remove_member', params: {
          'p_thread_id': _tid,
          'p_user_id': userId,
        });
      } catch (_) {
        await _sb.from('thread_members').delete()
            .eq('thread_id', _tid).eq('user_id', userId);
      }
      await _loadMembers();
      if (mounted) setState(() {});
      _snack('Removed');
    } on PostgrestException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Remove failed: $e');
    }
  }

  Future<void> _leaveGroup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave group?'),
        content: const Text('You will stop receiving messages from this group.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _sb.rpc('leave_group', params: {'p_thread_id': _tid});
      if (!mounted) return;
      Navigator.pop(context);
    } on PostgrestException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Could not leave group: $e');
    }
  }

  Future<void> _renameGroup() async {
    final controller = TextEditingController(text: _title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Group name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final newName = controller.text.trim();
    if (newName.isEmpty || newName == _title) return;

    try {
      try {
        await _sb.rpc('rename_group', params: {'p_thread_id': _tid, 'p_name': newName});
      } catch (_) {
        await _sb.from('threads').update({'name': newName}).eq('id', _tid);
      }
      setState(() => _title = newName);
      _snack('Group renamed');
    } on PostgrestException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Rename failed: $e');
    }
  }

  // ------------------ Inline download (per message) ------------------
  bool _isDownloading(String mid) => _dlCancels.containsKey(mid);

  Future<void> _startDownload({
    required String messageId,
    required String url,
    required String suggestedName,
  }) async {
    if (_isDownloading(messageId)) return;

    final cancelToken = CancelToken();
    _dlCancels[messageId] = cancelToken;
    _dlProgress[messageId] = 0.0;
    if (mounted) setState(() {});

    try {
      // Ensure filename has extension
      String name = suggestedName.trim();
      if (!name.contains('.')) {
        final fromUrl = _fileNameFromUrl(url);
        name = fromUrl.contains('.') ? fromUrl : '$fromUrl.bin';
      }

      final res = await Dio().get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes, followRedirects: true),
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (!mounted) return;
          if (!_dlProgress.containsKey(messageId)) return;
          if (total > 0) {
            _dlProgress[messageId] = received / total;
            setState(() {});
          }
        },
      );

      if (cancelToken.isCancelled) {
        _snack('Download canceled');
        return;
      }

      final bytes = Uint8List.fromList(res.data ?? const <int>[]);
      if (bytes.isEmpty) throw Exception('Empty file received.');

      _dlProgress[messageId] = 1.0;
      if (mounted) setState(() {});

      // Save via SAF
      final tmpDir = await getTemporaryDirectory();
      final tmpFile = File(p.join(tmpDir.path, name));
      await tmpFile.writeAsBytes(bytes, flush: true);

      _snack('Saving…');

      final savedTo = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          sourceFilePath: tmpFile.path,
          fileName: name,
        ),
      );

      if (savedTo == null || savedTo.isEmpty) {
        throw Exception('Save canceled or failed.');
      }

      _snack('Saved to: $savedTo');
    } catch (e) {
      if (!(e is DioException && CancelToken.isCancel(e))) {
        _snack('Download failed: $e');
      }
    } finally {
      _dlCancels.remove(messageId);
      _dlProgress.remove(messageId);
      if (mounted) setState(() {});
    }
  }

  void _cancelDownload(String messageId) {
    final token = _dlCancels[messageId];
    if (token != null && !token.isCancelled) {
      token.cancel('Canceled by user');
    }
  }

  // Small helper to render icon-only *pill* buttons
  Widget _iconPill({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton.outlined(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  // ------------------ UI ------------------
  @override
  Widget build(BuildContext context) {
    final visibleMessages = _messages.where((m) {
      final isHiddenByHideFeature = _hidden.contains(m['id']);
      if (isHiddenByHideFeature) return false;

      if (!_isGroup && _isPeerBlockedByMe && _peerId != null) {
        final messageSenderId = m['sender_id'] as String?;
        if (messageSenderId == _peerId) return false; // Hide if from blocked peer
      }
      return true;
    }).toList();


    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: <Widget>[
          if (_isGroup)
            IconButton(
              tooltip: 'Group info',
              icon: const Icon(Icons.group_outlined),
              onPressed: () async {
                await showModalBottomSheet(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (_) => _GroupInfoSheet(
                    members: _members,
                    ownerId: _ownerId,
                    myId: _myId,
                    onAddMembers: _openAddMembers,
                    onRemoveMember: _removeMember,
                  ),
                );
                await _loadMembers();
                if (mounted) setState(() {});
              },
            ),
          IconButton(
            tooltip: 'Call',
            icon: const Icon(Icons.call_outlined),
            onPressed: () => _openCallSheet(),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'block_toggle' && !_isGroup) _toggleBlockPeer();
              if (v == 'clear') _clearChatForMe();
              if (v == 'add' && _isGroup) _openAddMembers();
              if (v == 'rename' && _isGroup) _renameGroup();
              if (v == 'leave' && _isGroup) _leaveGroup();
            },
            itemBuilder: (context) {
              final items = <PopupMenuEntry<String>>[];
              if (!_isGroup && _peerId != null) {
                items.add(
                  PopupMenuItem<String>(
                    value: 'block_toggle',
                    child: Text(_isPeerBlockedByMe ? 'Unblock ${_title}' : 'Block ${_title}'),
                  ),
                );
              }
              items.add(const PopupMenuItem<String>(
                value: 'clear',
                child: Text('Clear chat for me'),
              ));
              if (_isGroup) {
                items.addAll(const [
                  PopupMenuItem<String>(value: 'add', child: Text('Add members')),
                  PopupMenuItem<String>(value: 'rename', child: Text('Rename group')),
                  PopupMenuItem<String>(value: 'leave', child: Text('Leave group')),
                ]);
              }
              return items;
            },
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
              itemCount: visibleMessages.length,
              itemBuilder: (context, i) {
                final m = visibleMessages[i];
                final isMe = m['sender_id'] == _myId;
                final senderId = m['sender_id'] as String?;
                final kind = (m['kind'] as String?) ?? 'text';
                final body = (m['body'] as String?) ?? '';
                final deleted = m['deleted_at'] != null || (kind == 'deleted');

                // Show sender name in groups when sender changes and it's not me
                bool showName = false;
                if (_isGroup) {
                  final prev = i > 0 ? visibleMessages[i - 1] : null;
                  final prevSender = prev?['sender_id'];
                  showName = !isMe && (prevSender != senderId);
                }

                // timestamp
                final raw = m['created_at'];
                DateTime ts = DateTime.now();
                if (raw is String) ts = DateTime.tryParse(raw) ?? ts;
                else if (raw is DateTime) ts = raw;

                // 1) Map preview (from columns or maps URL)
                final latCol = (m['location_lat'] as num?)?.toDouble();
                final lngCol = (m['location_lng'] as num?)?.toDouble();
                LatLng? point;
                if (!deleted) {
                  if (kind == 'location' && latCol != null && lngCol != null) {
                    point = LatLng(latCol, lngCol);
                  } else if (_isUrl(body)) {
                    point = _latLngFromMapsUrl(body);
                  }
                }
                if (point != null) {
                  final mapsUrl =
                      'https://www.google.com/maps/search/?api=1&query=${point.latitude},${point.longitude}';
                  return Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showName)
                            Padding(
                              padding: const EdgeInsets.only(left: 8, bottom: 2),
                              child: Text(
                                _displayName(senderId),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          Card(
                            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            child: InkWell(
                              onTap: () => _openUrl(mapsUrl),
                              onLongPress: () => _showMessageActions(m),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    height: 160,
                                    child: FlutterMap(
                                      options: MapOptions(
                                        initialCenter: point,
                                        initialZoom: 15,
                                        interactionOptions: const InteractionOptions(
                                          flags: InteractiveFlag.none,
                                        ),
                                      ),
                                      children: [
                                        // Use Carto tiles to avoid OSM "blocked" banners
                                        TileLayer(
                                          urlTemplate:
                                          'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                                          subdomains: const ['a', 'b', 'c', 'd'],
                                          userAgentPackageName: 'com.yourcompany.yourapp',
                                        ),
                                        MarkerLayer(markers: [
                                          Marker(
                                            point: point,
                                            width: 40,
                                            height: 40,
                                            child: const Icon(
                                              Icons.location_on,
                                              size: 36,
                                              color: Colors.red,
                                            ),
                                          ),
                                        ]),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    color: Theme.of(context).colorScheme.surface,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.map, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Open in Google Maps',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              decoration: TextDecoration.underline,
                                              color: Theme.of(context).colorScheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          timeOfDay(ts),
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // 2) File/media message card (URL with extension)
                final isLink = !deleted && _isUrl(body);
                final looksFile = isLink && _ext(_fileNameFromUrl(body)).isNotEmpty;

                if (!deleted && looksFile) {
                  final name = _fileNameFromUrl(body);
                  final isImg = _looksImage(name);
                  final isVid = _looksVideo(name);
                  final mid = m['id'] as String;
                  final downloading = _isDownloading(mid);
                  final prog = _dlProgress[mid] ?? 0.0;
                  final pct = (prog * 100).clamp(0, 100).toStringAsFixed(0);

                  // Header: image preview, simple video box, or generic file row
                  Widget header;
                  if (isImg) {
                    header = Hero(
                      tag: body,
                      child: Image.network(
                        body,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 180,
                          color: Colors.grey.shade300,
                          child: const Center(child: Icon(Icons.broken_image)),
                        ),
                      ),
                    );
                  } else if (isVid) {
                    header = SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(color: Colors.black12),
                          const Center(
                            child: CircleAvatar(
                              radius: 28,
                              backgroundColor: Colors.black45,
                              child: Icon(Icons.play_arrow, color: Colors.white, size: 34),
                            ),
                          ),
                        ],
                      ),
                    );
                  } else {
                    header = Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.insert_drive_file_outlined, size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showName)
                            Padding(
                              padding: const EdgeInsets.only(left: 8, bottom: 2),
                              child: Text(
                                _displayName(senderId),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          Card(
                            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onLongPress: () => _showMessageActions(m),
                              // Open videos/images inside the app
                              onTap: () => isVid
                                  ? _openVideo(body, title: name)
                                  : (isImg ? _openImage(body, title: name) : _openUrl(body)),
                              borderRadius: BorderRadius.circular(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  header,
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                    child: downloading
                                        ? Column(
                                      children: [
                                        LinearProgressIndicator(value: prog == 0 ? null : prog),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Text('$pct%',
                                                style: Theme.of(context).textTheme.labelMedium),
                                            const Spacer(),
                                            TextButton.icon(
                                              icon: const Icon(Icons.close),
                                              label: const Text('Cancel'),
                                              onPressed: () => _cancelDownload(mid),
                                            ),
                                          ],
                                        ),
                                      ],
                                    )
                                        : Row(
                                      children: [
                                        _iconPill(
                                          icon: Icons.download_rounded,
                                          tooltip: 'Download',
                                          onPressed: () => _startDownload(
                                            messageId: mid,
                                            url: body,
                                            suggestedName: name,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        _iconPill(
                                          icon: Icons.share_outlined,
                                          tooltip: 'Share',
                                          onPressed: () => Share.share(body, subject: name),
                                        ),
                                        const Spacer(),
                                        Text(
                                          timeOfDay(ts),
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // 3) Regular text bubble (includes link-only messages)
                final Color? textColor = deleted
                    ? Colors.grey.shade600
                    : (isLink ? Theme.of(context).colorScheme.primary : null);

                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showName)
                          Padding(
                            padding: const EdgeInsets.only(left: 8, bottom: 2),
                            child: Text(
                              _displayName(senderId),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        Card(
                          color: isMe ? Theme.of(context).colorScheme.primaryContainer : null,
                          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                          child: InkWell(
                            onLongPress: () => _showMessageActions(m),
                            onTap: isLink ? () => _openUrl(body) : null,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    deleted ? 'Message deleted' : body,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontStyle: deleted ? FontStyle.italic : FontStyle.normal,
                                      color: textColor,
                                      decoration: isLink ? TextDecoration.underline : TextDecoration.none,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    timeOfDay(ts),
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
              },
            ),
          ),
          const Divider(height: 1),
          ChatInputBar(
            enabled: !_isGroup && !_isPeerBlockedByMe && !_amIBlockedByPeer,
            onSendText: _sendText,
            onSendFiles: _sendFiles,
            onSendLocation: ({
              required double lat,
              required double lng,
              double? accuracyM,
            }) {
              return _sendLocation(lat: lat, lng: lng, accuracyM: accuracyM);
            },
          ),
        ],
      ),
    );
  }

  // ------------------ Misc ------------------
  Future<void> _clearChatForMe() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text(
            'This removes the conversation history for you. Others keep their messages.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _sb.rpc('hide_thread', params: {'p_thread_id': _tid});
      _cutoff = DateTime.now().toUtc();
      _messages.removeWhere((m) {
        final raw = m['created_at'];
        DateTime? ts;
        if (raw is String) ts = DateTime.tryParse(raw)?.toUtc();
        if (raw is DateTime) ts = raw.toUtc();
        return ts == null || !ts.isAfter(_cutoff!);
      });
      _hidden.clear();
      if (mounted) setState(() {});
      _snack('Chat cleared');
    } on PostgrestException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Clear failed: $e');
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
                title: Text(_isGroup ? 'Join audio room' : 'Audio call'),
                onTap: () {
                  Navigator.pop(context);
                  _startCall(video: false);
                }),
            ListTile(
                leading: const Icon(Icons.videocam),
                title: Text(_isGroup ? 'Join video room' : 'Video call'),
                onTap: () {
                  Navigator.pop(context);
                  _startCall(video: true);
                }),
          ],
        ),
      ),
    );
  }

  Future<void> _startCall({required bool video}) async {

    if (!_isGroup && _peerId != null) { // Only for 1v1 and if peerId is known
      if (_isPeerBlockedByMe) {
        _snack('You cannot call $_title. You have blocked them.', isError: true);
        return;
      }
      if (_amIBlockedByPeer) {
        _snack('You cannot call $_title. They have blocked you.', isError: true);
        return;
      }
    }

    final me = _myId;
    if (me == null) {
      _snack('Not signed in');
      return;
    }

    // GROUP: jump straight into the LiveKit room for this thread
    if (_isGroup) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupRoomScreen(
            threadId: _tid,
            title: _title,
            video: true, // false => audio-only join
          ),
        ),
      );
      return;
    }

    // 1v1: keep your ringing/invite flow
    try {
      final memRows = await _sb
          .from('thread_members')
          .select('user_id')
          .eq('thread_id', _tid);
      final others = (memRows as List)
          .map((m) => (m as Map)['user_id'] as String)
          .where((id) => id != me)
          .toList();
      if (others.length != 1) {
        _snack('Could not identify the other participant');
        return;
      }
      final inserted = await _sb
          .from('call_invites')
          .insert({
        'thread_id': _tid,
        'caller_id': me,
        'callee_id': others.first,
        'kind': video ? 'video' : 'audio',
      })
          .select('id')
          .single();
      if (!mounted) return;
      Navigator.pushNamed(
        context,
        AppRoutes.outgoingCall,
        arguments: OutgoingCallArgs(
          inviteId: inserted['id'] as String,
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

  String timeOfDay(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}

// ------------------ Group info sheet ------------------

class _GroupInfoSheet extends StatelessWidget {
  final Map<String, Map<String, dynamic>> members;
  final String? ownerId;
  final String? myId;
  final Future<void> Function() onAddMembers;
  final Future<void> Function(String userId) onRemoveMember;

  const _GroupInfoSheet({
    required this.members,
    required this.ownerId,
    required this.myId,
    required this.onAddMembers,
    required this.onRemoveMember,
  });

  @override
  Widget build(BuildContext context) {
    final entries = members.entries.toList()
      ..sort((a, b) {
        if (a.key == ownerId && b.key != ownerId) return -1;
        if (b.key == ownerId && a.key != ownerId) return 1;
        final an = _label(a.value).toLowerCase();
        final bn = _label(b.value).toLowerCase();
        return an.compareTo(bn);
      });

    final isOwner = ownerId != null && myId == ownerId;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.group),
              title: Text('Group members'),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: entries.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final e = entries[i];
                  final uid = e.key;
                  final owner = uid == ownerId;
                  final me = uid == myId;
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(_label(e.value)),
                    subtitle: Text(owner ? 'Owner' : (me ? 'You' : 'Member')),
                    trailing: (isOwner && !owner)
                        ? IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.person_remove),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Remove member?'),
                            content: Text('Remove ${_label(e.value)} from this group?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await onRemoveMember(uid);
                        }
                      },
                    )
                        : null,
                  );
                },
              ),
            ),
            const Divider(height: 1),
            if (isOwner)
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Add members'),
                  onPressed: onAddMembers,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _label(Map<String, dynamic> u) {
    final dn = (u['display_name'] as String?)?.trim();
    if (dn != null && dn.isNotEmpty) return dn;
    final email = (u['email'] as String?) ?? '';
    return email.isNotEmpty ? email.split('@').first : 'User';
  }
}
