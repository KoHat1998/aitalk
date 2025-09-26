import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_routes.dart';
import '../widgets/avatar.dart';
import '../widgets/empty_state.dart';
import 'thread_screen.dart'; // for ThreadArgs

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  /// Per-thread preview text (already filtered by cutoff & hides)
  final Map<String, String> _previews = {};

  /// Per-thread cutoff loaded from `thread_resets` for the signed-in user
  final Map<String, DateTime> _cutoffs = {};

  // ---- Ad banner ----
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;
  // Test unit id (ok to ship while testing)
  final String _bannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';

  Set<String> _blockedByUserIds = {}; // IDs of users the current user has blocked
  String? get _myUserId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    //_load();
    _loadAllChatData();
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
      size: AdSize.fullBanner,
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) {
          setState(() => _isBannerAdLoaded = true);
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          ad.dispose();
        },
      ),
    )..load();
  }

  Future<void> _loadAllChatData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      await _fetchBlockedUserIds(); // << FETCH BLOCKED USERS FIRST
      await _loadThreadsAndPreviews(); // Your existing method to load threads and compute previews
    } catch (e) {
      // Handle errors
      if (!mounted) return;
      _snack('Failed to load chat data: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchBlockedUserIds() async {
    final currentUserId = _myUserId;
    if (currentUserId == null) {
      _blockedByUserIds = {};
      return;
    }
    try {
      final response = await _sb
          .from('user_blocks') // Your blocks table name
          .select('blocked_user_id')
          .eq('blocker_user_id', currentUserId);

      if (mounted) {
        final ids = (response as List?)
            ?.map((item) => item['blocked_user_id'] as String)
            .where((id) => id.isNotEmpty) // Ensure no empty strings if possible
            .toSet();
        setState(() {
          _blockedByUserIds = ids ?? {};
        });
        print("DEBUG: ChatsScreen - Blocked User IDs: $_blockedByUserIds");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _blockedByUserIds = {}; // Reset on error
        });
        print("Error fetching blocked user IDs: $e");
        // Optionally show a snackbar, but maybe fail silently for this background fetch
      }
    }
  }

  Future<void> _loadThreadsAndPreviews() async {
    //setState(() => _loading = true);
    try {
      // 1) server-side list (expects columns from the updated list_threads())
      final res = await _sb.rpc('list_threads');
      final rows = (res as List?) ?? const [];
      _items = rows.cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

      // 2) load all user cutoffs once
      await _loadCutoffs();

      // 3) compute previews honoring cutoff + hides + soft-deletes
      await _refreshPreviews();

      if (mounted) setState(() {});
    } on PostgrestException catch (e) {
      if (!mounted) return;
      _snack('Failed to load chats: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to load chats: $e');
    } //finally {
      //if (mounted) setState(() => _loading = false);
    //}
  }

  Future<void> _loadCutoffs() async {
    _cutoffs.clear();
    try {
      final rows = await _sb.from('thread_resets').select('thread_id, cutoff_at');
      for (final r in (rows as List)) {
        final tid = r['thread_id'] as String?;
        final iso = r['cutoff_at'] as String?;
        if (tid != null && iso != null) {
          final dt = DateTime.tryParse(iso);
          if (dt != null) _cutoffs[tid] = dt.toUtc();
        }
      }
    } catch (_) {
      // No cutoffs yet or table missing -> fine
    }
  }

  // Title for a row (1v1 or group) – uses new RPC column
  String _titleFor(Map<String, dynamic> row) {
    final title = (row['display_name_for_list'] as String?)?.trim();
    if (title != null && title.isNotEmpty) return title;

    // Fallbacks if RPC didn’t populate (shouldn’t happen with the updated SQL)
    final isGroup = row['is_group'] == true;
    return isGroup ? 'Group' : 'User';
  }

  /// Compute last visible message per thread, respecting:
  /// - cutoff: ignore messages created_at <= cutoff_at
  /// - soft delete: deleted_at != null OR kind == 'deleted' -> "Message deleted"
  /// - delete-for-me: exclude messages present in message_hides for current user
  Future<void> _refreshPreviews() async {
    _previews.clear();

    for (final row in _items) {
      final tid = (row['thread_id'] as String?) ?? row['thread_id'].toString();
      final isGroup = row['is_group'] == true;
      final peerId = row['peer_id'] as String?;
      String defaultpreview = 'Say hi 👋';
      String finalPreview;

      //Block check
      if (!isGroup && peerId != null && _blockedByUserIds.contains(peerId)) {
        finalPreview = 'You blocked this user'; // Or "Interaction disabled"
        _previews[tid] = finalPreview;
        continue; // Skip fetching messages for preview if blocked
      }

      try {
        final cutoff = _cutoffs[tid];

        // Build the query with filters first, then order/limit
        var q = _sb
            .from('messages')
            .select('id, body, kind, deleted_at, created_at')
            .eq('thread_id', tid);

        if (cutoff != null) {
          q = q.gte('created_at', cutoff.toIso8601String());
        }

        final msgs = await q.order('created_at', ascending: false).limit(20);
        final list = (msgs as List).cast<Map>();

        if (list.isEmpty) {
          _previews[tid] = (row['last_message'] as String?) ?? defaultpreview;
          continue;
        }

        // Load "delete for me" hides for those messages
        final ids = list.map((m) => m['id'] as String).toList();
        final hides = await _sb
            .from('message_hides')
            .select('message_id')
            .or(ids.map((id) => 'message_id.eq.$id').join(','));
        final hiddenSet = {
          ...(hides as List).map((h) => h['message_id'] as String),
        };

        String? chosen;
        for (final m in list) {
          final mid = m['id'] as String;
          if (hiddenSet.contains(mid)) continue;

          final messageSenderId = m['sender_id'] as String?;
          if (!isGroup && peerId != null && _blockedByUserIds.contains(peerId) && messageSenderId == peerId) {
            // If we are here, it means the top-level block check didn't catch it,
            // which implies _blockedByUserIds might have updated.
            // We should use the "You blocked this user" message.
            // However, the `continue` above should prevent this inner loop mostly.
            // For safety, let's keep a simpler preview if a blocked user's message is somehow processed here.
            chosen = 'Interaction disabled'; // Or some other generic message
            break;
          }

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

        _previews[tid] = chosen ?? (row['last_message'] as String?) ?? defaultpreview;
      } catch (_) {
        _previews[tid] = (row['last_message'] as String?) ?? defaultpreview;
      }
    }
  }

  Future<void> _openThread(Map<String, dynamic> row) async {
    final threadId = (row['thread_id'] as String?) ?? row['thread_id'].toString();
    final title = _titleFor(row);
    final isGroup = row['is_group'] == true;
    final peerId = row['peer_id'] as String?;

    await Navigator.pushNamed(
      context,
      AppRoutes.thread,
      arguments: ThreadArgs(
        threadId: threadId,
        title: title,
        isGroup: isGroup,
        peerId: peerId,
      ),
    );
    if (mounted) _loadThreadsAndPreviews(); // refresh after returning
  }

  // ===== confirm dialog =====
  Future<bool> _confirmClearChat() async {
    final cs = Theme.of(context).colorScheme;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: cs.error),
            const SizedBox(width: 8),
            const Text('Clear chat history?'),
          ],
        ),
        content: const Text(
          'This clears your copy of the conversation and removes it from the list. '
              'New messages will show up as a fresh chat; old messages will not reappear.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ===== Clear chat history for me (sets cutoff and hides from list now) =====
  Future<void> _deleteChatForMe(Map<String, dynamic> row) async {
    final threadId = (row['thread_id'] as String?) ?? row['thread_id'].toString();

    final ok = await _confirmClearChat();
    if (!ok) return;

    try {
      // Your RPC that sets/updates thread_resets and hides it from list
      await _sb.rpc('reset_thread', params: {'p_thread_id': threadId});

      // Remove locally
      _items.removeWhere(
            (it) => ((it['thread_id'] as String?) ?? it['thread_id'].toString()) == threadId,
      );
      _previews.remove(threadId);
      _cutoffs.remove(threadId);

      if (mounted) setState(() {});
      _snack('Chat cleared');
    } on PostgrestException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Action failed: $e');
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
        onRefresh: _loadThreadsAndPreviews,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final row = _items[i];
            final title = _titleFor(row);
            final tid = (row['thread_id'] as String?) ?? row['thread_id'].toString();
            final isGroup = row['is_group'] == true;
            final peerId = row['peer_id'] as String?;

            bool isPeerChatBlocked = false;
            if (!isGroup && peerId != null && _blockedByUserIds.contains(peerId)) {
              isPeerChatBlocked = true;
            }

            String subtitle;
            if (isPeerChatBlocked) {
              subtitle = 'You blocked this user';
            } else {
              subtitle = _previews[tid] ?? (row['last_message'] as String?) ?? 'Say hi 👋';
            }

            final tile = Card(
              color: isPeerChatBlocked ? Colors.grey.shade300 : null,
              child: ListTile(
                leading: Avatar(
                  name: title,
                  // If your Avatar supports a url prop, you can pass:
                  // url: row['item_avatar_url'] as String?,
                ),
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isPeerChatBlocked ? Colors.grey.shade600 : null,
                  ),
                ),
                subtitle: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontStyle: isPeerChatBlocked ? FontStyle.italic : FontStyle.normal,
                      color: isPeerChatBlocked ? Colors.grey.shade700 : null,
                    ),
                ),
                onTap: () => _openThread(row),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'delete') _deleteChatForMe(row);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('Clear chat')),
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
                // We remove the item ourselves after a successful clear
                return false;
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
          Expanded(child: chatBody),
        ],
      ),
    );
  }
}
