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
  bool _loading = true;
  bool _saving = false;
  final _sb = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final u = _sb.auth.currentUser;
    if (u == null) {
      _snack('Not signed in');
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final row = await _sb
          .from('users')
          .select('display_name, email')
          .eq('id', u.id)
          .maybeSingle();

      final dn = (row?['display_name'] as String?)?.trim();
      _name.text = (dn != null && dn.isNotEmpty)
          ? dn
          : (u.email?.split('@').first.replaceAll(RegExp(r'[._]+'), ' ') ?? '');
    } catch (_) {
      _name.text =
          _sb.auth.currentUser?.email?.split('@').first.replaceAll(RegExp(r'[._]+'), ' ') ?? '';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final u = _sb.auth.currentUser;
    if (u == null) {
      _snack('Not signed in');
      return;
    }

    setState(() => _saving = true);
    final displayName = _name.text.trim();

    try {
      // Primary store: public.users (UPDATE your own row)
      final updated = await _sb
          .from('users')
          .update({'display_name': displayName, 'email': u.email})
          .eq('id', u.id)
          .select('id')
          .maybeSingle();

      // If your profile row never existed (e.g., trigger didn’t run), try insert.
      if (updated == null) {
        await _sb.from('users').insert({
          'id': u.id,
          'email': u.email,
          'display_name': displayName,
        });
      }

      // Mirror to auth metadata (optional)
      try {
        await _sb.auth.updateUser(
          UserAttributes(data: {'display_name': displayName}),
        );
      } catch (_) {/* non-fatal */}

      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Failed to save profile: $e');
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.person),
                  hintText: 'Display name',
                ),
                validator: (v) =>
                (v == null || v.trim().length < 2) ? 'Enter your name' : null,
              ),
              const Spacer(),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: _saving
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child:
                    CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
