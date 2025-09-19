import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FAQItem {
  final String q;
  final String a;
  const FAQItem(this.q, this.a);
}

class HelpSupportScreen extends StatefulWidget {
  final String userEmail; // Supabase auth email
  const HelpSupportScreen({super.key, required this.userEmail});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  // ---- Palette ----
  static const _bg     = Color(0xFF0C1117);
  static const _card   = Color(0xFF121923);
  static const _card2  = Color(0xFF0F151E);
  static const _stroke = Color.fromARGB(30, 255, 255, 255);
  static const _label  = Color(0xCCFFFFFF);
  static const _muted  = Color(0x99FFFFFF);
  static const _accent = Color(0xFF3B82F6);
  static const _ok     = Color(0xFF22C55E);

  final _formKey = GlobalKey<FormState>();
  final _commentCtrl = TextEditingController();
  bool _sending = false;

  // ---- Status tracking ----
  Map<String, dynamic>? _latestTicket; // {id,status,created_at}
  RealtimeChannel? _ticketChannel;
  static const List<String> _steps = ['submitted', 'reviewing', 'completed'];

  final List<FAQItem> _faqs = const [
    FAQItem('How to change my name?', 'Go to Settings → Edit Profile → change your display name → Save.'),
    FAQItem('How to delete a message?', 'Press and hold an existing message for ~2 seconds, then choose Delete.'),
    FAQItem('Within what time can messages be permanently deleted?', 'Messages can be permanently deleted within 2 hours of sending.'),
  ];

  @override
  void initState() {
    super.initState();
    _loadLatestTicket();
  }

  @override
  void dispose() {
    _ticketChannel?.unsubscribe();
    _commentCtrl.dispose();
    super.dispose();
  }

  // ---------- Data ----------

  String? _validateComment(String? v) {
    final s = (v ?? '').trim();
    if (s.length < 10) return 'Please write at least 10 characters';
    return null;
  }

  Future<void> _loadLatestTicket() async {
    try {
      final row = await Supabase.instance.client
          .from('support_tickets')
          .select('id,status,created_at')
          .eq('user_email', widget.userEmail)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (!mounted) return;
      setState(() => _latestTicket = row);

      if (row != null) _subscribeToTicket(row['id'] as int);
    } catch (_) {
      // ignore; UI shows "No active ticket"
    }
  }

  void _subscribeToTicket(int id) {
    final sb = Supabase.instance.client;
    _ticketChannel?.unsubscribe();

    _ticketChannel = sb.channel('ticket_$id').onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'support_tickets',
      callback: (payload) {
        final rec = payload.newRecord;
        if (rec == null || rec['id'] != id) return; // manual filter
        if (!mounted) return;
        setState(() {
          _latestTicket = {
            'id': rec['id'],
            'status': rec['status'],
            'created_at': rec['created_at'],
          };
        });
      },
    ).subscribe();
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
      // Create ticket (status defaults to 'submitted')
      final row = await Supabase.instance.client
          .from('support_tickets')
          .insert({
        'user_email': widget.userEmail,
        'message'   : _commentCtrl.text.trim(),
        'source'    : 'mobile',
      })
          .select('id,status,created_at')
          .single();

      if (!mounted) return;

      setState(() => _latestTicket = row);
      _subscribeToTicket(row['id'] as int);

      // Optional: notify admin (Edge Function)
      Supabase.instance.client.functions.invoke(
        'admin-email',
        body: {
          'ticketId': row['id'].toString(),
          'email': widget.userEmail,
          'message': _commentCtrl.text.trim(),
        },
      ).catchError((_) {});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report sent! Ticket #${row['id']}')),
      );
      _commentCtrl.clear();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Network error: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ---------- Theme & helpers ----------

  ThemeData _theme(BuildContext context) {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: _bg,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18),
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
      // ✅ FIX 2: CardThemeData (not CardTheme)
      cardTheme: const CardThemeData(
        color: _card,
        surfaceTintColor: Colors.transparent,
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

  int _stepIndex(String status) {
    final i = _steps.indexOf(status.toLowerCase());
    return i < 0 ? 0 : i;
  }

  Color _dotColor(int i, int cur) {
    // When completed, make ALL dots green
    final completed = (_latestTicket?['status'] as String?)
        ?.toLowerCase() == 'completed';
    if (completed) return _ok;

    // Otherwise: passed = green, current = blue, upcoming = muted
    return i < cur ? _ok : (i == cur ? _accent : _muted);
  }

  Color _lineColor(int i, int cur) {
    // When completed, make ALL segments green
    final completed = (_latestTicket?['status'] as String?)
        ?.toLowerCase() == 'completed';
    if (completed) return _ok;

    // Otherwise: segments before current are green
    return i < cur ? _ok : _stroke;
  }

  Widget _tracker() {
    final t = _latestTicket;
    if (t == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Card(
          child: ListTile(
            leading: const Icon(Icons.timelapse),
            title: const Text('No active ticket'),
            subtitle: const Text('Submit a report to start tracking its status.'),
            trailing: IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _loadLatestTicket,
            ),
          ),
        ),
      );
    }

    final status = (t['status'] as String?)?.toLowerCase() ?? 'submitted';
    final idx = _stepIndex(status);
    final id = t['id'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.assignment_turned_in_rounded),
                const SizedBox(width: 8),
                Text('Ticket #$id', style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadLatestTicket,
                ),
              ]),
              const SizedBox(height: 10),
              Row(
                children: List.generate(_steps.length * 2 - 1, (i) {
                  if (i.isOdd) {
                    final seg = i ~/ 2;
                    return Expanded(child: Container(height: 2, color: _lineColor(seg + 1, idx)));
                  } else {
                    final dot = i ~/ 2;
                    final isCur = dot == idx;
                    return Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: _dotColor(dot, idx).withOpacity(isCur ? 1 : 0.25),
                        shape: BoxShape.circle,
                        border: Border.all(color: _dotColor(dot, idx)),
                      ),
                      child: Center(
                        child: Icon(
                          dot < idx ? Icons.check : (dot == idx ? Icons.radio_button_checked : Icons.circle),
                          size: 14,
                        ),
                      ),
                    );
                  }
                }),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('Submitted',         style: TextStyle(color: _muted, fontSize: 12)),
                  Text('Reviewing',         style: TextStyle(color: _muted, fontSize: 12)),
                  Text('Feedback complete', style: TextStyle(color: _muted, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
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
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Card(
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: _accent.withOpacity(.15), shape: BoxShape.circle),
                      child: const Icon(Icons.support_agent, size: 20, color: Colors.white),
                    ),
                    title: const Text('We’re here to help', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('Signed in as ${widget.userEmail}', style: const TextStyle(color: _muted)),
                  ),
                ),
              ),

              // Send report
              _sectionHeader('Send Report'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _sending ? null : _send,
                            icon: _sending
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.send_rounded),
                            label: Text(_sending ? 'Sending…' : 'Send to Support'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Status tracker
              _sectionHeader('Ticket Status'),
              _tracker(),

              // FAQs
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
                              ),
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
