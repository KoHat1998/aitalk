import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_routes.dart';
import 'thread_screen.dart';

class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen({super.key});
  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final _sb = Supabase.instance.client;
  final _code = TextEditingController();
  bool _busy = false;

  Future<void> _join() async {
    final input = _code.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter group ID or code')));
      return;
    }
    setState(() => _busy = true);
    try {
      String? threadId;

      // Try as UUID ID first
      final uuidRegex = RegExp(r'^[0-9a-fA-F-]{32,36}$');
      if (uuidRegex.hasMatch(input)) {
        await _sb.rpc('join_group', params: {'p_thread_id': input});
        threadId = input;
      } else {
        final tid = await _sb.rpc('join_group_by_code', params: {'p_code': input});
        threadId = (tid as String?) ?? tid?.toString();
      }

      // Fetch group name for header
      final t = await _sb.from('threads').select('name').eq('id', threadId!).single();
      final title = (t['name'] as String?)?.trim().isNotEmpty == true ? t['name'] as String : 'Group';

      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.thread,
        arguments: ThreadArgs(threadId: threadId, title: title, isGroup: true),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Join failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join group')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _code,
              decoration: const InputDecoration(
                labelText: 'Group ID or code',
                hintText: 'UUID or 8-char code',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _join,
              icon: const Icon(Icons.group_add),
              label: const Text('Join'),
            ),
          ],
        ),
      ),
    );
  }
}
