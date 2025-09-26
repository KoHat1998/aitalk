import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/avatar.dart';
import '../../models/blocked_user.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<BlockedUserInfo> _blockedUsers = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchBlockedUsers();
  }

  Future<void> _fetchBlockedUsers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        _errorMessage = "You need to be logged in to view blocked users.";
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final response = await _supabase
          .from('user_blocks')
          .select('blocked_user_id, blocked_profile:users!user_blocks_blocked_user_id_fkey!inner(id, display_name, email, avatar_url)')
          .eq('blocker_user_id', currentUserId) // RLS also enforces this
          .order('created_at', ascending: false); // Optional: order by when they were blocked

      if (!mounted) return;

      _blockedUsers = response.map((item) {
        // The joined data from 'users' table will be under the alias 'blocked_profile'
        final userProfileData = item['blocked_profile'] as Map<String, dynamic>;
        return BlockedUserInfo.fromMap(userProfileData);
      }).toList();

    } on PostgrestException catch (e) {
      if (!mounted) return;
      _errorMessage = "Error fetching blocked users: ${e.message}";
      print('Supabase fetch blocked users error: ${e.toString()}');
    } catch (e) {
      if (!mounted) return;
      _errorMessage = "An unexpected error occurred: $e";
      print('Generic fetch blocked users error: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _displayTitleForUser(BlockedUserInfo user) {
    if (user.displayName != null && user.displayName!.isNotEmpty) {
      return user.displayName!;
    }
    if (user.email != null && user.email!.isNotEmpty) {
      return user.email!.split('@').first; // Show username part of email
    }
    return 'User (ID: ${user.userId.substring(0, 6)}...)'; // Fallback
  }

  Future<void> _unblockUser(String userIdToUnblock) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need to be logged in.')),
      );
      return;
    }

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm Unblock'),
        content: Text('Are you sure you want to unblock ${_displayTitleForUser(_blockedUsers.firstWhere((u) => u.userId == userIdToUnblock))}?'),
        actions: <Widget>[
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.primary),
            child: const Text('Unblock'),
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );

    if (confirm != true) return; // User cancelled

    try {
      await _supabase
          .from('user_blocks')
          .delete()
          .match({'blocker_user_id': currentUserId, 'blocked_user_id': userIdToUnblock});

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User unblocked successfully.')),
        );
        // Refresh the list to remove the unblocked user
        _fetchBlockedUsers();
      }
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error unblocking user: ${e.toString()}')),
        );
      }
      print('Error unblocking user: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocked Users'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_errorMessage!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      )
          : _blockedUsers.isEmpty
          ? const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'You haven\'t blocked anyone yet.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      )
          : RefreshIndicator( // Added RefreshIndicator
        onRefresh: _fetchBlockedUsers,
        child: ListView.separated(
          itemCount: _blockedUsers.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final user = _blockedUsers[index];
            final title = _displayTitleForUser(user);
            return ListTile(
              leading: Avatar(name: title, imageUrl: user.avatarUrl),
              title: Text(title),
              subtitle: user.email != null ? Text(user.email!) : null,
              trailing: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary, // Or Colors.blue
                ),
                onPressed: () => _unblockUser(user.userId),
                child: const Text('Unblock'),
              ),
            );
          },
        ),
      ),
    );
  }
}