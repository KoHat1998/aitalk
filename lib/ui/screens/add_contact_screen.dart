import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_routes.dart';

class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});
  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _sb = Supabase.instance.client;
  final _codeCtrl = TextEditingController();
  Map<String, dynamic>? _result;
  bool _searching = false;
  bool _adding = false;

  Future<void> _find() async {
    final code = _codeCtrl.text.trim().toLowerCase();
    if (code.isEmpty) return;
    setState(() { _searching = true; _result = null; });
    try {
      final res = await _sb.rpc('lookup_user_by_code', params: {'p_code': code});

      Map<String, dynamic>? row;
      if (res is List && res.isNotEmpty) {
        row = Map<String, dynamic>.from(res.first as Map);
      } else if (res is Map) {
        row = Map<String, dynamic>.from(res);
      }

      if (row == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No user found for that code')));
        }
      } else {
        _result = row;
      }
      if (mounted) setState(() {});
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }


  Future<void> _scan() async {
    final scanned = await Navigator.pushNamed(context, AppRoutes.scanQr) as String?;
    if (scanned != null && scanned.isNotEmpty) {
      _codeCtrl.text = scanned;
      await _find();
    }
  }

  Future<void> _add() async {
    final me = _sb.auth.currentUser?.id;
    final targetId = _result?['id'] as String?;
    if (me == null || targetId == null) return;

    if (me == targetId) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("You can't add yourself")));
      return;
    }

    setState(() => _adding = true);
    try {
      // 🔑 call server-side mutual add (creates A->B and B->A)
      await _sb.rpc('add_contact_mutual', params: {'p_contact': targetId});

      if (!mounted) return;
      Navigator.pop(context, true); // success → refresh list
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Add failed: $e')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final found = _result != null;
    final name = (found ? (_result!['display_name'] as String?) : null) ?? '';
    final email = (found ? (_result!['email'] as String?) : null) ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Add Contact')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(
            controller: _codeCtrl,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Enter friend code',
              prefixIcon: Icon(Icons.qr_code_2),
            ),
            onSubmitted: (_) => _find(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _searching ? null : _find,
                  child: _searching
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Find'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (found)
            Card(
              child: ListTile(
                leading: const Icon(Icons.person),
                title: Text(name.isNotEmpty ? name : 'No name'),
                subtitle: Text(email),
                trailing: FilledButton(
                  onPressed: _adding ? null : _add,
                  child: _adding
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Add'),
                ),
              ),
            ),
          if (!found && !_searching)
            Text('Ask your friend to show their code/QR in Settings → “My code”.',
                style: TextStyle(color: Colors.grey.shade600)),
        ]),
      ),
    );
  }
}
