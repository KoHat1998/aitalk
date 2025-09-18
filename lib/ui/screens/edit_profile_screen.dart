import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  bool _saving = false;
  final _sb = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    final u = _sb.auth.currentUser;
    // preload best current name
    final metaName = u?.userMetadata?['display_name']?.toString();
    _name.text = metaName?.trim().isNotEmpty == true
        ? metaName!.trim()
        : (u?.email?.split('@').first.replaceAll(RegExp(r'[._]+'), ' ') ?? '');
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final u = _sb.auth.currentUser;
      if (u == null) throw Exception('Not signed in');
      final displayName = _name.text.trim();

      // 1) Update auth metadata (so tokens/devices agree)
      await _sb.auth.updateUser(
        UserAttributes(data: {'display_name': displayName}),
      );

      // 2) Upsert profile row in public.users
      await _sb.from('users').upsert({
        'id': u.id,
        'email': u.email,
        'display_name': displayName,
      }, onConflict: 'id');

      if (!mounted) return;
      Navigator.pop(context, true); // signal success
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Failed to save profile');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.person), hintText: 'Display name'),
              validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your name' : null,
            ),
            const Spacer(),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
