import 'package:flutter/material.dart';
import 'package:sabai/ui/screens/news_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_routes.dart';
import 'contacts_screen.dart';
import 'chats_screen.dart';
import 'settings_screen.dart';
import 'incoming_call_screen.dart' show IncomingCallArgs;

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int idx = 0;
  final pages = const [ContactsScreen(), ChatsScreen(), NewsScreen(), SettingsScreen()];

  final _sb = Supabase.instance.client;
  RealtimeChannel? _incomingChan;

  @override
  void initState() {
    super.initState();
    _listenIncomingCalls();
  }

  @override
  void dispose() {
    if (_incomingChan != null) _sb.removeChannel(_incomingChan!);
    super.dispose();
  }

  void _listenIncomingCalls() {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;

    _incomingChan = _sb
        .channel('realtime:call_invites:incoming:$uid')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'call_invites',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'callee_id',
        value: uid,
      ),
      callback: (payload) async {
        final rec = payload.newRecord;
        if (rec == null) return;
        if ((rec['status'] as String?) != 'ringing') return;

        final inviteId = rec['id'] as String;
        final threadId = rec['thread_id'] as String;
        final isVideo = ((rec['kind'] as String?) ?? 'video') != 'audio';

        // Resolve caller display name
        String callerName = 'Incoming call';
        try {
          final callerId = rec['caller_id'] as String;
          final u = await _sb
              .from('users')
              .select('display_name,email')
              .eq('id', callerId)
              .maybeSingle();
          if (u != null) {
            final dn = (u['display_name'] as String?)?.trim() ?? '';
            final em = u['email'] as String? ?? '';
            callerName = dn.isNotEmpty ? dn : (em.isNotEmpty ? em.split('@').first : callerName);
          }
        } catch (_) {}

        if (!mounted) return;
        Navigator.pushNamed(
          context,
          AppRoutes.incomingCall,
          arguments: IncomingCallArgs(
            inviteId: inviteId,
            threadId: threadId,
            callerName: callerName,
            video: isVideo,
          ),
        );
      },
    )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[idx],
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => setState(() => idx = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Contacts'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.newspaper_outlined), selectedIcon: Icon(Icons.newspaper), label: 'NewsFeed'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
      floatingActionButton: idx == 0
          ? FloatingActionButton(
        onPressed: () => Navigator.pushNamed(context, AppRoutes.newGroup),
        child: const Icon(Icons.add),
      )
          : null,
    );
  }
}
