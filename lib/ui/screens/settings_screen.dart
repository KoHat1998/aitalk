// lib/features/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_routes.dart';
import '../../core/push_token.dart';            // ✅ rotate & register FCM tokens
import '../widgets/avatar.dart';
import 'ai_talk_screen.dart';
import 'package:sabai/features/support/help_support_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _sb = Supabase.instance.client;

  bool _msgNoti = true;
  bool _groupNoti = true;
  bool _readReceipts = true;

  Future<Map<String, dynamic>?> _fetchProfile() async {
    final user = _sb.auth.currentUser;
    if (user == null) return null;
    final data = await _sb
        .from('users')
        .select('display_name, email, avatar_url, contact_code')
        .eq('id', user.id)
        .maybeSingle();
    return data;
  }

  String _nameFromEmail(String email) {
    final base = email.split('@').first;
    return base.replaceAll(RegExp(r'[._]+'), ' ').trim();
  }

  /// Sign out that **rotates** the device token so the next account on this
  /// device gets a fresh token (prevents “token sticks to first account”).
  Future<void> _signOut() async {
    try {
      // 1) Rotate token FIRST (delete DB row + device token)
      await PushToken.rotateOnLogout();
    } catch (_) {}

    try {
      // 2) End auth session
      await _sb.auth.signOut();
    } catch (_) {}

    if (!mounted) return;

    // 3) Go to sign-in
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.signIn, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _fetchProfile(),
        builder: (context, snap) {
          final user = _sb.auth.currentUser;
          final loading = snap.connectionState == ConnectionState.waiting;

          final dbDisplay = (snap.data?['display_name'] as String?)?.trim();
          final dbEmail = (snap.data?['email'] as String?)?.trim();
          final code = (snap.data?['contact_code'] as String?)?.trim();

          final metaDisplay =
          user?.userMetadata?['display_name']?.toString().trim();
          final email =
          (dbEmail?.isNotEmpty ?? false) ? dbEmail! : (user?.email ?? '');

          final displayName = (dbDisplay?.isNotEmpty ?? false)
              ? dbDisplay!
              : ((metaDisplay?.isNotEmpty ?? false)
              ? metaDisplay!
              : (email.isNotEmpty ? _nameFromEmail(email) : 'Your Name'));

          final avatarLabel =
          displayName.isNotEmpty ? displayName : (email.isNotEmpty ? email : 'User');

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: Avatar(name: avatarLabel, size: 46),
                  title: Text(
                    displayName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(email.isNotEmpty ? email : 'Not signed in'),
                  trailing: FilledButton.tonal(
                    onPressed: () async {
                      final changed = await Navigator.pushNamed(
                          context, AppRoutes.editProfile);
                      if (changed == true && mounted) setState(() {});
                    },
                    child: const Text('Edit Profile'),
                  ),
                ),
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                ),
              const SizedBox(height: 12),

              // --- My friend code
              if (code != null && code.isNotEmpty)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.qr_code_2),
                    title: Text(code),
                    subtitle: const Text('My code'),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          tooltip: 'Copy',
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: code));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Code copied')),
                            );
                          },
                        ),
                        IconButton(
                          tooltip: 'Show QR',
                          icon: const Icon(Icons.open_in_new),
                          onPressed: () =>
                              Navigator.pushNamed(context, AppRoutes.myCode),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),
              const Text('Notification Preferences',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Card(
                child: SwitchListTile(
                  title: const Text('Message Notifications'),
                  value: _msgNoti,
                  onChanged: (v) => setState(() => _msgNoti = v),
                ),
              ),
              Card(
                child: SwitchListTile(
                  title: const Text('Group Notifications'),
                  value: _groupNoti,
                  onChanged: (v) => setState(() => _groupNoti = v),
                ),
              ),
              Card(
                child: SwitchListTile(
                  title: const Text('Read Receipts'),
                  value: _readReceipts,
                  onChanged: (v) => setState(() => _readReceipts = v),
                ),
              ),

              const SizedBox(height: 16),
              const Text('App Settings',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('Help & Support'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    final authEmail =
                        Supabase.instance.client.auth.currentUser?.email ?? '';
                    if (authEmail.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please sign in to contact support.'),
                        ),
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HelpSupportScreen(userEmail: authEmail),
                      ),
                    );
                  },
                ),
              ),

              // --- AI TALK navigation
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('AI TALK'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AiTalkScreen(),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Logout'),
                  onTap: _signOut, // ✅ rotates token then signs out
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
