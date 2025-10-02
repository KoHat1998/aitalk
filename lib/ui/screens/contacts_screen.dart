import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_routes.dart';
import '../widgets/avatar.dart';
import 'thread_screen.dart';

// Ringing flow
import 'outgoing_call_screen.dart' show OutgoingCallArgs;

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _sb = Supabase.instance.client;
  final _search = TextEditingController();
  late final VoidCallback _searchListener;

  bool _loading = true;

  List<String> _orderedIds = [];
  final Map<String, Map<String, dynamic>> _profiles = {};

  @override
  void initState() {
    super.initState();
    _searchListener = () => setState(() {});
    _search.addListener(_searchListener);
    _load();
  }

  @override
  void dispose() {
    _search.removeListener(_searchListener);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = _sb.auth.currentUser?.id;
      if (me == null) {
        _orderedIds = [];
        _profiles.clear();
        setState(() => _loading = false);
        return;
      }

      final rows = await _sb
          .from('contacts')
          .select('contact_id, created_at')
          .eq('owner_id', me)
          .order('created_at', ascending: false);

      final ids = <String>[];
      final seen = <String>{};
      for (final r in rows as List) {
        final id = (r['contact_id'] as String?) ?? '';
        if (id.isNotEmpty && !seen.contains(id)) {
          seen.add(id);
          ids.add(id);
        }
      }

      _orderedIds = ids;
      _profiles.clear();

      if (ids.isEmpty) {
        setState(() {});
        return;
      }

      final orClause = ids.map((id) => 'id.eq.$id').join(',');
      final profRows = await _sb
          .from('users')
          .select('id, display_name, email, avatar_url, contact_code')
          .or(orClause);

      for (final p in profRows as List) {
        final m = Map<String, dynamic>.from(p as Map);
        _profiles[m['id'] as String] = m;
      }

      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load contacts: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.text.trim().toLowerCase();
    final list = <Map<String, dynamic>>[];
    for (final id in _orderedIds) {
      final p = _profiles[id];
      if (p == null) continue;
      if (q.isEmpty) {
        list.add(p);
      } else {
        final name = (p['display_name'] as String?)?.toLowerCase() ?? '';
        final email = (p['email'] as String?)?.toLowerCase() ?? '';
        if (name.contains(q) || email.contains(q)) list.add(p);
      }
    }
    return list;
  }

  String _titleFor(Map<String, dynamic> c) {
    final name = (c['display_name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = (c['email'] as String?) ?? '';
    return email.isNotEmpty ? email.split('@').first : 'User';
  }

  Future<void> _openAddContact() async {
    final added = await Navigator.pushNamed(context, AppRoutes.addContact);
    if (added == true) {
      await _load();
    }
  }

  Future<String> _checkBlockStatus(String peerId) async {
    final me = _sb.auth.currentUser?.id;
    if (me == null) return 'error';

    try {
      final iBlockedThem = await _sb
          .from('user_blocks')
          .select('id')
          .match({'blocker_user_id' : me, 'blocked_user_id' : peerId})
          .maybeSingle();
      if (iBlockedThem != null) {
        return 'blocked';
      }

      final theyBlockedMe = await _sb
          .from('user_blocks')
          .select('id')
          .match({'blocker_user_id' : peerId, 'blocked_user_id' : me})
          .maybeSingle();
      if (theyBlockedMe != null) {
        return 'blocked_by_peer';
      }
      return 'none';
    } catch (e) {
      print('Error checking block status: $e');
      return 'error';
    }
  }

  // Chat: resolve/create a 1v1 then open ThreadScreen
  Future<void> _openOrCreate1v1(Map<String, dynamic> contact) async {
    final peerId = contact['id'] as String?;
    if (peerId == null) return;
    // --- Block Check ---
    final blockStatus = await _checkBlockStatus(peerId);
    if (mounted) { // Check mounted before showing SnackBar
      if (blockStatus == 'blocked_by_me') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You have blocked this user. Unblock them from the "Blocked Users" screen to chat.')),
        );
        return;
      } else if (blockStatus == 'blocked_by_peer') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You cannot chat with this user as they have blocked you.')),
        );
        return;
      } else if (blockStatus == 'error') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not verify block status. Please try again.')),
        );
        return;
      }
    }

    try {
      final res = await _sb.rpc('resolve_1v1', params: {'p_target': peerId});
      final tid = (res is String) ? res : (res?.toString());
      if (tid == null || tid.isEmpty) throw Exception('No thread id returned');

      if (!mounted) return;
      Navigator.pushNamed(
        context,
        AppRoutes.thread,
        arguments: ThreadArgs(threadId: tid, title: _titleFor(contact), peerId: peerId, isGroup: false),
      );
    } on PostgrestException catch (e) {
      if (e.code == '23505' || (e.message ?? '').toLowerCase().contains('duplicate 1v1')) {
        try {
          final r = await _sb.rpc('get_existing_1v1', params: {'p_target': peerId});
          final tid = (r is String) ? r : (r?.toString());
          if (tid != null && tid.isNotEmpty && mounted) {
            Navigator.pushNamed(
              context,
              AppRoutes.thread,
              arguments: ThreadArgs(threadId: tid, title: _titleFor(contact), peerId: peerId, isGroup: false),
            );
            return;
          }
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open chat: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open chat: $e')),
      );
    }
  }

  // Call via ringing flow (insert invite -> OutgoingCallScreen)
  // Default is audio-first (video=false)
  Future<void> _startCall(Map<String, dynamic> contact, {bool video = false}) async {
    final peerId = contact['id'] as String?;
    if (peerId == null) return;

    final blockStatus = await _checkBlockStatus(peerId);
    if (mounted) { // Check mounted before showing SnackBar
      if (blockStatus == 'blocked') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You have blocked this user. Unblock them to make a call.')),
        );
        return;
      } else if (blockStatus == 'blocked_by_peer') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You cannot call this user as they have blocked you.')),
        );
        return;
      } else if (blockStatus == 'error') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not verify block status. Please try again.')),
        );
        return;
      }
    }

    try {
      // Resolve/create 1v1 thread
      var res = await _sb.rpc('resolve_1v1', params: {'p_target': peerId});
      String? tid = (res is String) ? res : (res?.toString());
      if (tid == null || tid.isEmpty) {
        res = await _sb.rpc('get_existing_1v1', params: {'p_target': peerId});
        tid = (res is String) ? res : (res?.toString());
      }
      if (tid == null || tid.isEmpty) throw Exception('No thread id');

      // Create invite row (kind reflects audio/video intent at start)
      final me = _sb.auth.currentUser!.id;
      final inserted = await _sb
          .from('call_invites')
          .insert({
        'thread_id': tid,
        'caller_id': me,
        'callee_id': peerId,
        'kind': video ? 'video' : 'audio',
      })
          .select('id')
          .single();

      final inviteId = inserted['id'] as String;
      final title = _titleFor(contact);

      if (!mounted) return;
      Navigator.pushNamed(
        context,
        AppRoutes.outgoingCall,
        arguments: OutgoingCallArgs(
          inviteId: inviteId,
          threadId: tid,
          calleeName: title,
          video: video, // will be false by default (audio-first)
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Call error: $e')),
      );
    }
  }

  // Delete contact via RPC (both sides)
  Future<void> _deleteContact(String contactUserId) async {
    final cs = Theme.of(context).colorScheme;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove contact?'),
        content: const Text('You will be removed from each other’s contacts.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _sb.rpc('delete_contact', params: {'target': contactUserId});

      _profiles.remove(contactUserId);
      _orderedIds.removeWhere((id) => id == contactUserId);
      if (mounted) setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact removed')),
        );
      }
    } on PostgrestException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Delete failed: $e');
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _initiateBlockUser(String userIdToBlock, String userNameToBlock) async {
    final currentUserId = _sb.auth.currentUser?.id;
    if (currentUserId == null) {
      _snack('You need to be logged in to block users.');
      return;
    }
    if (currentUserId == userIdToBlock) {
      _snack('You cannot block yourself.');
      return;
    }

    // Optional: Confirmation Dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Block $userNameToBlock?'),
        content: Text('Are you sure you want to block $userNameToBlock? You will no longer see their posts, and they will not be able to call or message you. You can unblock them later from the "Blocked Users" screen.'),
        actions: <Widget>[
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error), // Use error color for block
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
        'blocked_user_id': userIdToBlock,
      });
      _snack('$userNameToBlock has been blocked.');
      // Optional: You might want to refresh some state here if the UI
      // should immediately change for this contact (e.g., disable chat/call buttons).
      // For now, the next attempt to chat/call will pick up the block.
      // Or, if this screen shows an indicator for blocked users, update it.
      setState(() {}); // Basic refresh to rebuild contact tiles if their state changes

    } on PostgrestException catch (e) {
      if (e.code == '23505') { // Unique constraint violation (already blocked)
        _snack('$userNameToBlock is already blocked.');
      } else {
        _snack('Error blocking user: ${e.message}');
      }
      print('Error blocking user: ${e.toString()}');
    } catch (e) {
      _snack('An unexpected error occurred while blocking.');
      print('Generic error blocking user: ${e.toString()}');
    }
  }

  Widget _contactTile(Map<String, dynamic> c) {
    final title = _titleFor(c);
    final email = (c['email'] as String?) ?? '';
    final contactId = c['id'] as String? ?? '';

    /*final deleteBtn = IconButton(
      tooltip: 'Delete',
      onPressed: () => _deleteContact(contactId),
      icon: const Icon(Icons.delete_outline),
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFF0E141C),
        foregroundColor: Theme.of(context).colorScheme.error,
      ),
    );

    final blockBtn = IconButton(
      tooltip: 'Block User',
      icon: const Icon(Icons.block, color: Colors.orangeAccent), // Or another distinct color
      onPressed: () => _initiateBlockUser(contactId, title),
    );*/

    return Card(
      child: ListTile(
        leading: Avatar(name: title),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        //subtitle: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Wrap(spacing: 8, children: [
          IconButton(
            tooltip: 'Message',
            icon: const Icon(Icons.chat_bubble_outline),
            color: Colors.blue,
            onPressed: () => _openOrCreate1v1(c),
          ),
          // AUDIO-FIRST: phone icon starts audio call (video: false)
          IconButton(
            tooltip: 'Call',
            icon: const Icon(Icons.call_outlined),
            color: Colors.blue,
            onPressed: () => _startCall(c, video: false),
            // (Optional) long-press could open a sheet for "Start with video"
          ),
          //blockBtn,
          //deleteBtn,
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.blue,),
            tooltip: "More options",
            onSelected: (value) {
              if (value == 'block') {
                _initiateBlockUser(contactId, title);
              } else if (value == 'delete') {
                _deleteContact(contactId);
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'block', // You'll need logic to show "Unblock" if already blocked
                child: ListTile(leading: Icon(Icons.block, color: Colors.orangeAccent), title: Text('Block User')),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('Delete Contact')),
              ),
            ],
          ),
        ]),
        onTap: () => _openOrCreate1v1(c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            tooltip: 'Blocked Users',
            icon: const Icon(Icons.app_blocking),
            onPressed: (){
              Navigator.pushNamed(context, AppRoutes.blockedUsers);
            },
          ),
          IconButton(
            tooltip: 'Add contact',
            icon: const Icon(Icons.person_add_alt),
            onPressed: _openAddContact,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'mycode':
                  Navigator.pushNamed(context, AppRoutes.myCode);
                  break;
                case 'scan':
                  Navigator.pushNamed(context, AppRoutes.scanQr);
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'mycode', child: Text('My code')),
              PopupMenuItem(value: 'scan', child: Text('Scan QR')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search contacts…',
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                ? _EmptyContacts(onAdd: _openAddContact)
                : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final c = items[i];
                  final contactId = c['id'] as String? ?? 'unknown_$i';

                  return Dismissible(
                    key: ValueKey('contact_$contactId'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      color: Colors.red,
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    confirmDismiss: (_) async {
                      await _deleteContact(contactId);
                      return false; // we already updated the list
                    },
                    child: _contactTile(c),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            showDragHandle: true,
            builder: (_) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.person_add_alt),
                    title: const Text('Add contact by code'),
                    onTap: () {
                      Navigator.pop(context);
                      _openAddContact();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.group_add),
                    title: const Text('New group'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, AppRoutes.newGroup);
                    },
                  ),
                ],
              ),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _EmptyContacts extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyContacts({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            const Text('No contacts yet', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Add someone with their friend code to start chatting.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAdd, child: const Text('Add contact')),
          ],
        ),
      ),
    );
  }
}