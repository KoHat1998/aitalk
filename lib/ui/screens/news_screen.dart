import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Assuming these models and screens exist in these locations:
import '../../models/user_post.dart';
import '../../models/stories_model.dart'; // Import your story models
import '../../utils/storage_utils.dart'; // For extractPathFromUrl
import './create_post.dart'; // Your CreatePostScreen
import './edit_post_screen.dart';   // Your EditPostScreen
import './create_story_screen.dart'; // Placeholder for your CreateStoryScreen
import './story_view_screen.dart';   // Placeholder for your StoryViewScreen

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  final _supabase = Supabase.instance.client;
  List<UserPost> _posts = [];
  bool _isLoadingPosts = true; // Renamed for clarity
  String? _postErrorMessage;  // Renamed for clarity

  List<UserStoryGroup> _storyGroups = [];
  bool _isLoadingStories = true;
  String? _storyErrorMessage;

  // No need for the currentUserId getter if not directly used in this file's logic
  // final String? currentAuthUserId = _supabase.auth.currentUser?.id; // Can be fetched when needed

  @override
  void initState() {
    super.initState();
    _loadInitialFeedData();
  }

  Future<void> _loadInitialFeedData() async {
    // Set combined loading state if you want a single initial loader
    if (mounted) {
      setState(() {
        _isLoadingPosts = true;
        _isLoadingStories = true;
      });
    }
    await Future.wait([
      _fetchPosts(),
      _fetchAndGroupStories(),
    ]);
  }

  Future<void> _fetchPosts() async {
    if (!mounted) return;
    // No need to set _isLoadingPosts = true here if _loadInitialFeedData does it
    // Or if this is called independently for refresh, then yes:
    if (!_isLoadingPosts) setState(() => _isLoadingPosts = true);
    setState(() => _postErrorMessage = null);


    try {
      final currentAuthUserId = _supabase.auth.currentUser?.id;
      final response = await _supabase.rpc(
        'get_posts_with_reaction_details',
        params: {'requesting_user_id': currentAuthUserId},
      );

      if (!mounted) return;

      if (response is List) {
        _posts = response.map((item) {
          return UserPost(
            id: item['id'] as String,
            userId: item['user_id'] as String,
            content: item['content'] as String?,
            imageUrl: item['image_url'] as String?,
            createdAt: DateTime.parse(item['created_at'] as String),
            userDisplayName: item['author_display_name'] as String?,
            userAvatarUrl: item['author_avatar_url'] as String?,
            likeCount: (item['like_count'] as num?)?.toInt() ?? 0,
            currentUserHasLiked: item['current_user_has_liked'] as bool? ?? false,
          );
        }).toList();
      } else {
        _postErrorMessage = "Unexpected data format for posts.";
        print('Supabase RPC unexpected response type: ${response.runtimeType}');
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      _postErrorMessage = "Post Fetch Error: ${e.message}";
      print('Supabase post fetch error: ${e.toString()}');
    } catch (e) {
      if (!mounted) return;
      _postErrorMessage = "An unexpected error occurred fetching posts: $e";
      print('Generic post fetch error: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPosts = false;
        });
      }
    }
  }

  Future<void> _fetchAndGroupStories() async {
    if (!mounted) return;
    // No need to set _isLoadingStories = true here if _loadInitialFeedData does it
    // Or if this is called independently for refresh, then yes:
    if (!_isLoadingStories) setState(() => _isLoadingStories = true);
    setState(() => _storyErrorMessage = null);

    try {
      final response = await _supabase
          .from('stories')
          .select('''
            id, user_id, media_url, media_type, caption, created_at,
            user:user_id (id, display_name, avatar_url)
          ''')
          .order('user_id', ascending: true)
          .order('created_at', ascending: true);

      if (!mounted) return; // Check after await

      final List<dynamic> data = response as List<dynamic>;
      if (data.isEmpty) {
        if (mounted) {
          setState(() {
            _storyGroups = [];
          });
        }
      } else {
        final Map<String, UserStoryGroup> tempGroups = {};
        for (var storyData in data) {
          final Map<String, dynamic> storyMap = storyData as Map<String, dynamic>;
          final String userId = storyMap['user_id'] as String;
          final Map<String, dynamic>? userData = storyMap['user'] as Map<String, dynamic>?;

          if (!tempGroups.containsKey(userId)) {
            tempGroups[userId] = UserStoryGroup(
              userId: userId,
              userName: userData?['display_name'] as String? ?? 'User',
              userAvatarUrl: userData?['avatar_url'] as String?,
              stories: [],
            );
          }
          tempGroups[userId]!.stories.add(StoryItem.fromMap(storyMap));
        }
        if (mounted) {
          setState(() {
            _storyGroups = tempGroups.values.toList();
          });
        }
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      _storyErrorMessage = "Story Fetch Error: ${e.message}";
      print('Supabase story fetch error: ${e.toString()}');
    } catch (e) {
      if (!mounted) return;
      _storyErrorMessage = "An unexpected error occurred fetching stories: $e";
      print('Generic story fetch error: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingStories = false;
        });
      }
    }
  }

  void _navigateToCreatePost() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreatePostScreen()),
    );
    if (result == true && mounted) {
      _fetchPosts();
    }
  }

  void _navigateToAddStoryScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreateStoryScreen()), // Ensure this screen exists
    );
    if (result == true && mounted) {
      _fetchAndGroupStories();
    }
  }

  Future<void> _toggleLike(UserPost postToUpdate) async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be logged in to like posts')),
        );
      }
      return;
    }

    final currentUserId = currentUser.id;
    final wasLiked = postToUpdate.currentUserHasLiked;
    final newLikeCount = wasLiked ? postToUpdate.likeCount - 1 : postToUpdate.likeCount + 1;

    final postIndex = _posts.indexWhere((p) => p.id == postToUpdate.id);
    if (postIndex != -1) {
      if (!mounted) return;
      setState(() {
        _posts[postIndex] = _posts[postIndex].copyWith(
          currentUserHasLiked: !wasLiked,
          likeCount: newLikeCount < 0 ? 0 : newLikeCount,
        );
      });
    }

    try {
      if (wasLiked) {
        await _supabase
            .from('post_reactions')
            .delete()
            .match({'post_id': postToUpdate.id, 'user_id': currentUserId, 'reaction_type': 'like'});
      } else {
        await _supabase.from('post_reactions').insert({
          'post_id': postToUpdate.id,
          'user_id': currentUserId,
          'reaction_type': 'like',
        });
      }
    } catch (e) {
      if (postIndex != -1 && mounted) {
        setState(() {
          _posts[postIndex] = _posts[postIndex].copyWith(
            currentUserHasLiked: wasLiked,
            likeCount: postToUpdate.likeCount,
          );
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing like: ${e.toString()}')),
        );
      }
      print("Error toggling like: $e");
    }
  }

  Widget _buildPostItem(UserPost post) {
    final currentAuthUserId = _supabase.auth.currentUser?.id;
    final bool isAuthor = post.userId == currentAuthUserId;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: post.userAvatarUrl != null && post.userAvatarUrl!.isNotEmpty
                      ? NetworkImage(post.userAvatarUrl!)
                      : null,
                  child: post.userAvatarUrl == null || post.userAvatarUrl!.isEmpty
                      ? Text(post.userDisplayName?.isNotEmpty == true ? post.userDisplayName![0].toUpperCase() : 'U')
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    post.userDisplayName ?? 'Anonymous User',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                if (isAuthor)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _navigateToEditPost(post);
                      } else if (value == 'delete') {
                        _confirmDeletePost(post);
                      }
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'edit',
                        child: ListTile(leading: Icon(Icons.edit), title: Text('Edit')),
                      ),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: ListTile(leading: Icon(Icons.delete), title: Text('Delete')),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (post.content != null && post.content!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(post.content!, style: const TextStyle(fontSize: 15)),
              ),
            if (post.imageUrl != null && post.imageUrl!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8.0),
                  child: Image.network(
                    post.imageUrl!,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, exception, stackTrace) {
                      return Container(
                        height: 150,
                        color: Colors.grey[200],
                        child: const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 50)),
                      );
                    },
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              'Posted: ${post.createdAt.toLocal().toString().substring(0, 16)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    icon: Icon(
                      post.currentUserHasLiked ? Icons.favorite : Icons.favorite_border,
                      color: post.currentUserHasLiked ? Colors.red : Theme.of(context).iconTheme.color,
                      size: 20,
                    ),
                    label: Text(
                      'Like',
                      style: TextStyle(
                        color: post.currentUserHasLiked ? Colors.red : Theme.of(context).textTheme.labelLarge?.color,
                      ),
                    ),
                    onPressed: () => _toggleLike(post),
                  ),
                  if (post.likeCount > 0)
                    Text(
                      '${post.likeCount} ${post.likeCount == 1 ? "like" : "likes"}',
                      style: TextStyle(color: Colors.grey[700], fontSize: 14),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToEditPost(UserPost post) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => EditPostScreen(postToEdit: post)),
    ).then((result) {
      if (result == true && mounted) {
        _fetchPosts();
      }
    });
  }

  Future<void> _confirmDeletePost(UserPost post) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: const Text('Are you sure you want to delete this post?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context, false),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) return;

    // Show loading indicator specifically for delete operation
    // For simplicity, we are using the global _isLoadingPosts,
    // but a dedicated _isDeletingPost would be better for granular UI.
    setState(() => _isLoadingPosts = true);

    try {
      if (post.imageUrl != null && post.imageUrl!.isNotEmpty) {
        final imagePath = extractPathFromUrl(post.imageUrl!); // Ensure extractPathFromUrl is robust
        if (imagePath != null && imagePath.isNotEmpty) {
          try {
            await _supabase.storage.from('post_images').remove([imagePath]);
          } catch (storageError) {
            print('Error removing image from storage: $storageError (Continuing with post deletion)');
            // Optionally show a non-fatal warning to the user
          }
        }
      }
      await _supabase.from('posts').delete().eq('id', post.id);

      if (mounted) {
        // _fetchPosts(); // This will reset loading state
        // Optimistic UI update: Remove post locally then fetch
        _posts.removeWhere((p) => p.id == post.id);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post deleted')));
        // If _posts becomes empty, the UI will show "No posts yet".
        // No need to call _fetchPosts() immediately if you want faster perceived deletion,
        // but the list will be fully accurate on next refresh/re-fetch.
        // For this example, let's keep the fetch for consistency.
        _fetchPosts(); // This will re-fetch and also set _isLoadingPosts = false
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DB Error deleting post: ${e.message}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting post: $e')));
      }
    } finally {
      // _fetchPosts() will handle setting _isLoadingPosts to false
      // If you didn't call _fetchPosts() above, you'd do:
      // if (mounted && _isLoadingPosts) {
      //   setState(() => _isLoadingPosts = false);
      // }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("User Feed"),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Add Story',
            onPressed: _navigateToAddStoryScreen,
          ),
        ],
      ),
      body: (_isLoadingPosts && _posts.isEmpty && _isLoadingStories && _storyGroups.isEmpty)
          ? const Center(child: CircularProgressIndicator())
          : _buildFeedContent(),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToCreatePost,
        tooltip: 'Create Post',
        child: const Icon(Icons.add_comment_outlined),
      ),
    );
  }

  Widget _buildFeedContent() {
    return RefreshIndicator(
      onRefresh: _loadInitialFeedData,
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: _buildStorySection(),
          ),
          _buildPostsListSliver(),
        ],
      ),
    );
  }

  Widget _buildStorySection() {
    if (_isLoadingStories && _storyGroups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.0)),
      );
    }
    if (_storyErrorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(_storyErrorMessage!, style: TextStyle(color: Colors.orange[700]), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              ElevatedButton(onPressed: _fetchAndGroupStories, child: const Text('Retry Stories'))
            ]
        ),
      );
    }
    if (_storyGroups.isEmpty && !_isLoadingStories) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
        child: Text(
          'No stories yet. Tap the + in the top right to share yours!',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return _buildStoryRingsWidget();
  }

  Widget _buildStoryRingsWidget() {
    return SizedBox(
      height: 110,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
        scrollDirection: Axis.horizontal,
        // No "Add Story" button here, it's in the AppBar
        itemCount: _storyGroups.length,
        itemBuilder: (context, index) {
          final group = _storyGroups[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StoryViewScreen(storyGroups: _storyGroups, initialGroupIndex: index),
                      ),
                    );
                  },
                  child: CircleAvatar(
                    radius: 30,
                    backgroundImage: group.userAvatarUrl != null && group.userAvatarUrl!.isNotEmpty
                        ? NetworkImage(group.userAvatarUrl!)
                        : null,
                    child: (group.userAvatarUrl == null || group.userAvatarUrl!.isEmpty)
                        ? Text(group.userName.isNotEmpty ? group.userName[0].toUpperCase() : "U")
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox( // Added SizedBox to constrain width of username text
                  width: 60, // Match CircleAvatar diameter
                  child: Text(
                    group.userName,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPostsListSliver() {
    if (_isLoadingPosts && _posts.isEmpty) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_postErrorMessage != null && _posts.isEmpty) {
      return SliverFillRemaining(child: _buildErrorWidget(_postErrorMessage!, _fetchPosts));
    }
    if (_posts.isEmpty && !_isLoadingPosts) {
      return const SliverFillRemaining(
        child: Center(
          child: Padding( // Added padding for better visual
            padding: EdgeInsets.all(16.0),
            child: Text(
              'No posts from your contacts yet. Posts from users you are connected with will appear here.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) {
          final post = _posts[index];
          return _buildPostItem(post);
        },
        childCount: _posts.length,
      ),
    );
  }

  Widget _buildErrorWidget(String message, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.red[700], fontSize: 16)),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onRetry, child: const Text('Try Again'))
          ],
        ),
      ),
    );
  }
}
