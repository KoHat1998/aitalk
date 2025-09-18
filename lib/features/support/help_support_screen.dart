import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Simple model for FAQ items (kept top-level for compatibility)
class FAQItem {
  final String q;
  final String a;
  const FAQItem(this.q, this.a);
}

class HelpSupportScreen extends StatefulWidget {
  /// Pass the signed-in user's email (from Supabase auth)
  final String userEmail;
  const HelpSupportScreen({super.key, required this.userEmail});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  // --- Dark palette to match your Settings UI ---
  static const _bg     = Color(0xFF0C1117);
  static const _card   = Color(0xFF121923);
  static const _card2  = Color(0xFF0F151E);
  static const _stroke = Color.fromARGB(30, 255, 255, 255); // faint white divider
  static const _label  = Color(0xCCFFFFFF);
  static const _muted  = Color(0x99FFFFFF);
  static const _accent = Color(0xFF3B82F6);

  final _formKey = GlobalKey<FormState>();
  final _commentCtrl = TextEditingController();
  bool _sending = false;

  final List<FAQItem> _faqs = const [
    FAQItem('How to change my name?', 'Go to Settings → Edit Profile → change your display name → Save.'),
    FAQItem('How to delete a message?', 'Press and hold an existing message for ~2 seconds, then choose Delete.'),
    FAQItem('Within what time can messages be permanently deleted?', 'Messages can be permanently deleted within 2 hours of sending.'),
  ];

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  String? _validateComment(String? v) {
    final s = (v ?? '').trim();
    if (s.length < 10) return 'Please write at least 10 characters';
    return null;
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;

    if (Supabase.instance.client.auth.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to send a report.')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      // 1) Save the ticket in Supabase
      final row = await Supabase.instance.client
          .from('support_tickets')
          .insert({
        'user_email': widget.userEmail,
        'message': _commentCtrl.text.trim(),
        'source': 'mobile',
      })
          .select('id')
          .single();

      final id = row['id'].toString();

      // 2) 🚀 Notify admin via your Edge Function (fire-and-forget)
      Supabase.instance.client.functions.invoke(
        'admin-email', // <-- your function slug
        body: {
          'ticketId': id,
          'email': widget.userEmail,
          'message': _commentCtrl.text.trim(),
        },
      ).catchError((_) {
        // ignore email failure; ticket is already saved
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report sent! Ticket #$id')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  ThemeData _theme(BuildContext context) {
    return ThemeData(
      // useMaterial3: true, // optional
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: _bg,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: const TextStyle(color: _muted),
        hintStyle: const TextStyle(color: _muted),
        filled: true,
        fillColor: _card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _accent, width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      // IMPORTANT: some Flutter versions require CardThemeData (not CardTheme)
      cardTheme: CardThemeData(
        color: _card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _stroke),
        ),
      ),
      textTheme: Theme.of(context).textTheme.apply(
        bodyColor: _label,
        displayColor: _label,
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: _accent,
        brightness: Brightness.dark,
        background: _bg,
        surface: _card,
        primary: _accent,
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: _card2,
        border: Border(bottom: BorderSide(color: _stroke)),
      ),
      child: Text(title, style: const TextStyle(color: _muted, fontWeight: FontWeight.w600)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _theme(context),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Help & Support'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Card(
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _accent.withOpacity(.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.support_agent, size: 20, color: Colors.white),
                    ),
                    title: const Text('We’re here to help', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('Signed in as ${widget.userEmail}', style: const TextStyle(color: _muted)),
                  ),
                ),
              ),

              _sectionHeader('Send Report'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _commentCtrl,
                      minLines: 5,
                      maxLines: 10,
                      decoration: const InputDecoration(
                        labelText: 'Describe your issue / feedback',
                        hintText: 'Tell us what happened…',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                      ),
                      validator: _validateComment,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _sending ? null : _send,
                            icon: _sending
                                ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                                : const Icon(Icons.send_rounded),
                            label: Text(_sending ? 'Sending…' : 'Send to Support'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              _sectionHeader('FAQs'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Card(
                  child: Column(
                    children: List.generate(_faqs.length, (i) {
                      final item = _faqs[i];
                      final isLast = i == _faqs.length - 1;
                      return Column(
                        children: [
                          ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            title: Text(item.q, style: const TextStyle(fontWeight: FontWeight.w600)),
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(item.a, style: const TextStyle(color: _muted)),
                              )
                            ],
                          ),
                          if (!isLast) const Divider(height: 1, color: _stroke),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
