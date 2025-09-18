import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/app_routes.dart';
import '../widgets/empty_state.dart';
import 'thread_screen.dart'; // for ThreadArgs
import '../widgets/avatar.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  // Computed, per-thread preview (respects hides & soft-delete)
  final Map<String, String> _previews = {};

  //AD banner
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  final String _bannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';

  @override
  void initState() {
    super.initState();
    _load();
    _loadBannerAd();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId,
      request: const AdRequest(),
      size: AdSize.largeBanner, // Or AdSize.largeBanner, AdSize.fullBanner, etc.
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) {
          debugPrint('$BannerAd loaded.');
          setState(() {
            _isBannerAdLoaded = true;
          });
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          debugPrint('$BannerAd failedToLoad: $error');
          ad.dispose();
        },
        // Other listener events can be handled here (onAdOpened, onAdClosed, etc.)
      ),
    )..load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _sb.rpc('list_threads');
      final rows = (res as List?) ?? const [];
      _items = rows.cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

      // Compute previews that honor "delete for me" and "delete for everyone"
      await _refreshPreviews();
      if (mounted) setState(() {});
    } on PostgrestException catch (e) {
      if (!mounted) return;
      _snack('Failed to load chats: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to load chats: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Build a title for a thread row (1v1 or group)
  String _titleFor(Map<String, dynamic> row) {
    final type = (row['type'] as String?) ?? '1v1';
    if (type == '1v1') {
      final dn = (row['other_display_name'] as String?)?.trim();
      if (dn != null && dn.isNotEmpty) return dn;
      final email = (row['other_email'] as String?) ?? '';
      return email.isNotEmpty ? email.split('@').first : 'User';
    }
    return (row['name'] as String?)?.trim().isNotEmpty == true
        ? row['name'] as String
        : 'Group';
  }

  // Compute last visible message per thread, respecting:
  // - soft delete: deleted_at != null OR kind == 'deleted' -> "Message deleted"
  // - delete-for-me: exclude messages present in message_hides for current user
  // We fetch only a small tail (e.g. 20) to find the first visible preview.
  Future<void> _refreshPreviews() async {
    _previews.clear();
    for (final row in _items) {
      final tid = (row['thread_id'] as String?) ?? row['thread_id'].toString();
      String preview = 'Say hi 👋';

      try {
        // Pull a small tail of recent messages
        final msgs = await _sb
            .from('messages')
            .select('id, body, kind, deleted_at, created_at')
            .eq('thread_id', tid)
            .order('created_at', ascending: false)
            .limit(20);

        final list = (msgs as List).cast<Map>();

        if (list.isEmpty) {
          // fall back to server-provided summary or friendly prompt
          preview = (row['last_message'] as String?) ?? preview;
          _previews[tid] = preview;
          continue;
        }

        // Load hides for those messages for the current user
        final ids = list.map((m) => m['id'] as String).toList();
        final hides = await _sb
            .from('message_hides')
            .select('message_id')
            .or(ids.map((id) => 'message_id.eq.$id').join(','));

        final hiddenSet = {
          ...(hides as List).map((h) => h['message_id'] as String),
        };

        // Pick the first non-hidden message; if soft-deleted, show placeholder
        String? chosen;
        for (final m in list) {
          final mid = m['id'] as String;
          if (hiddenSet.contains(mid)) continue;

          final isDeleted =
              m['deleted_at'] != null || (m['kind'] as String?) == 'deleted';
          if (isDeleted) {
            chosen = 'Message deleted';
            break;
          }

          final body = (m['body'] as String?)?.trim();
          if (body != null && body.isNotEmpty) {
            chosen = body;
            break;
          }
        }

        preview = chosen ??
            (row['last_message'] as String?) ??
            preview;
      } catch (_) {
        // On any error, fall back to server’s last_message (if provided)
        preview = (row['last_message'] as String?) ?? preview;
      }

      _previews[tid] = preview;
    }
  }

  Future<void> _openThread(Map<String, dynamic> row) async {
    final threadId = (row['thread_id'] as String?) ?? row['thread_id'].toString();
    final title = _titleFor(row);
    await Navigator.pushNamed(
      context,
      AppRoutes.thread,
      arguments: ThreadArgs(
        threadId: threadId,
        title: title,
        isGroup: (row['type'] == 'group'),
      ),
    );
    if (mounted) _load(); // refresh previews after returning
  }

  // ===== Delete chat (hide thread for current user only) =====
  Future<void> _deleteChatForMe(Map<String, dynamic> row) async {
    final threadId = (row['thread_id'] as String?) ?? row['thread_id'].toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete chat?'),
        content: const Text(
          'This removes the conversation from your Chats list. '
              'Other participants will keep their history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      // Server-side: mark this thread hidden for current user
      await _sb.rpc('hide_thread', params: {'p_thread_id': threadId});

      // Local: remove from list & previews
      _items.removeWhere(
            (it) => ((it['thread_id'] as String?) ?? it['thread_id'].toString()) == threadId,
      );
      _previews.remove(threadId);

      if (mounted) setState(() {});
      _snack('Chat deleted');
    } on PostgrestException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Delete failed: $e');
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    Widget chatBody;

    if (_loading) {
      chatBody = const Center(child: CircularProgressIndicator());
    } else if (_items.isEmpty) {
      chatBody = const EmptyState(
        icon: Icons.chat_bubble_outline,
        title: 'No chats yet',
        subtitle: 'Your recent conversations will appear here.',
      );
    } else {
      chatBody = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final row = _items[i];
            final title = _titleFor(row);
            final tid = (row['thread_id'] as String?) ?? row['thread_id'].toString();
            final subtitle = _previews[tid] ?? (row['last_message'] as String?) ?? 'Say hi 👋';

            final tile = Card(
              child: ListTile(
                leading: Avatar(name: title),
                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _openThread(row),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'delete') _deleteChatForMe(row);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('Delete chat')),
                  ],
                ),
              ),
            );

            return Dismissible(
              key: ValueKey('chat_$tid'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                color: Colors.red,
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              confirmDismiss: (_) async {
                await _deleteChatForMe(row);
                return false; // we already removed locally if successful
              },
              child: tile,
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: Column(
        children: [
          if (_isBannerAdLoaded && _bannerAd != null)
            Container(
              alignment: Alignment.center,
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
          Expanded(
              child: chatBody,
            ),
        ],
      )
    );
  }
}
