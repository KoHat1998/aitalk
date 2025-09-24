import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_routes.dart';
import '../widgets/avatar.dart';
import 'thread_screen.dart';

class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key});
  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final _sb = Supabase.instance.client;
  final _name = TextEditingController();

  bool _loading = true;     // loading contacts
  bool _creating = false;   // creating group

  // contact_id -> profile
  final Map<String, Map<String, dynamic>> _profiles = {};
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() => _loading = true);
    try {
      final me = _sb.auth.currentUser?.id;
      if (me == null) throw Exception('Not signed in');

      final rows = await _sb
          .from('contacts')
          .select('contact_id, created_at')
          .eq('owner_id', me)
          .order('created_at', ascending: false);

      final ids = <String>[];
      final seen = <String>{};
      for (final r in rows as List) {
        final id = (r['contact_id'] as String?) ?? '';
        if (id.isNotEmpty && seen.add(id)) ids.add(id);
      }

      if (ids.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      final orClause = ids.map((id) => 'id.eq.$id').join(',');
      final profs = await _sb
          .from('users')
          .select('id, display_name, email, avatar_url')
          .or(orClause);

      _profiles
        ..clear()
        ..addEntries((profs as List).map((p) {
          final m = Map<String, dynamic>.from(p as Map);
          return MapEntry(m['id'] as String, m);
        }));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Load failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _titleFor(Map<String, dynamic> p) {
    final dn = (p['display_name'] as String?)?.trim();
    if (dn != null && dn.isNotEmpty) return dn;
    final email = (p['email'] as String?) ?? '';
    return email.isNotEmpty ? email.split('@').first : 'User';
  }

  Future<void> _create() async {
    if (_creating) return;
    final name = _name.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a group name')));
      return;
    }
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select at least 1 member')));
      return;
    }

    final me = _sb.auth.currentUser?.id;
    if (me == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Not signed in')));
      return;
    }

    setState(() => _creating = true);
    try {
      // Let the RPC handle membership (it will include the creator and seed the initial system message).
      final members = _selected.toList();

      final res = await _sb.rpc('create_group', params: {
        'p_name': name,
        'p_member_ids': members,
      });

      final tid = res is String
          ? res
          : (res is Map && res['thread_id'] is String ? res['thread_id'] as String : null);

      if (tid == null || tid.isEmpty) {
        throw Exception('create_group did not return a thread id');
      }

      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.thread,
        arguments: ThreadArgs(threadId: tid, title: name, isGroup: true),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Create failed: $e')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _profiles.values.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('New group')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _name,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Group name',
                hintText: 'eg. Weekend Gang',
              ),
              onSubmitted: (_) => _create(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (items.isEmpty
                ? const Center(child: Text('No contacts yet'))
                : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final p = items[i];
                final id = p['id'] as String;
                final title = _titleFor(p);
                final selected = _selected.contains(id);
                return Card(
                  child: ListTile(
                    leading: Avatar(name: title),
                    title: Text(title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Checkbox(
                      value: selected,
                      onChanged: (_) {
                        setState(() {
                          if (selected) {
                            _selected.remove(id);
                          } else {
                            _selected.add(id);
                          }
                        });
                      },
                    ),
                    onTap: () {
                      setState(() {
                        if (selected) {
                          _selected.remove(id);
                        } else {
                          _selected.add(id);
                        }
                      });
                    },
                  ),
                );
              },
            )),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creating ? null : _create,
        icon: _creating
            ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        )
            : const Icon(Icons.group_add),
        label: Text(_creating ? 'Creating…' : 'Create'),
      ),
    );
  }
}
