
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user_post.dart';
import '../../utils/storage_utils.dart';
import 'create_post.dart';
import 'edit_post_screen.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  final _supabase = Supabase.instance.client;
  List<UserPost> _posts = [];
  bool _isLoading = true;
  String? _errorMessage;

  String? get currentUserId {
    return null; // Or your test user ID
  }


  @override
  void initState() {
    super.initState();
    _fetchPosts();
  }

  Future<void> _fetchPosts() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentAuthUserId = _supabase.auth.currentUser?.id;

      // Call the RPC function
      final response = await _supabase.rpc(
        'get_posts_with_reaction_details',
        params: {'requesting_user_id': currentAuthUserId}, // Pass null if user not logged in
      );

      if (!mounted) return;

      if (response is List) { // RPC returns a list of records
        _posts = response.map((item) {
          return UserPost(
            id: item['id'] as String,
            userId: item['user_id'] as String,
            content: item['content'] as String?,
            imageUrl: item['image_url'] as String?,
            createdAt: DateTime.parse(item['created_at'] as String),
            userDisplayName: item['author_display_name'] as String?,
            userAvatarUrl: item['author_avatar_url'] as String?,
            likeCount: (item['like_count'] as num?)?.toInt() ?? 0, // Ensure num to int conversion
            currentUserHasLiked: item['current_user_has_liked'] as bool? ?? false,
          );
        }).toList();
      } else {
        _errorMessage = "Unexpected data format from server.";
        print('Supabase RPC unexpected response type: ${response.runtimeType}');
      }

    } on PostgrestException catch (e) {
      if (!mounted) return;
      _errorMessage = "Data Fetch Error: ${e.message} (Code: ${e.code})";
      print('Supabase fetch error: ${e.toString()}');
    } catch (e) {
      if (!mounted) return;
      _errorMessage = "An unexpected error occurred: $e";
      print('Generic fetch error: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToCreatePost() async {
    // Before navigating, ensure you know who the current user is.
    // For this simplified example, we'll pass a placeholder or handle it in CreatePostScreen.
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CreatePostScreen()),
    );

    // If a post was successfully created (result == true), refresh the feed.
    if (result == true && mounted) {
      _fetchPosts();
    }
  }

  Future<void> _toggleLike(UserPost postToUpdate) async {
    if (_supabase.auth.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be logged in to like posts')));
      return;
    }

    final currentUserId = _supabase.auth.currentUser!.id;
    final wasLiked = postToUpdate.currentUserHasLiked;
    final newLikeCount = wasLiked ? postToUpdate.likeCount - 1 : postToUpdate.likeCount + 1;

    final postIndex = _posts.indexWhere((p) => p.id == postToUpdate.id);
    if (postIndex != -1) {
      if (!mounted) return;
      setState(() {
        _posts[postIndex] = _posts[postIndex].copyWith(
          currentUserHasLiked: !wasLiked,
          likeCount: newLikeCount < 0 ? 0 : newLikeCount, // Ensure count doesn't go below 0
        );
      });
    }

    try {
      if (wasLiked) {
        // User is unliking the post
        await _supabase
            .from('post_reactions')
            .delete()
            .match({'post_id': postToUpdate.id, 'user_id': currentUserId, 'reaction_type': 'like'});
      } else {
        // User is liking the post
        await _supabase.from('post_reactions').insert({
          'post_id': postToUpdate.id,
          'user_id': currentUserId,
          'reaction_type': 'like', // Explicitly set if not relying on default
        });
      }
      // Optional: You might want to re-fetch the specific post's accurate data
      // or trust the optimistic update for now and let the next full _fetchPosts correct it.
      // For simplicity, we'll rely on the next full refresh or optimistic update for now.

    } catch (e) {
      // Revert optimistic update on error
      if (postIndex != -1) {
        if (!mounted) return;
        setState(() {
          _posts[postIndex] = _posts[postIndex].copyWith(
            currentUserHasLiked: wasLiked, // Revert to original liked state
            likeCount: postToUpdate.likeCount, // Revert to original like count
          );
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error processing like: ${e.toString()}')));
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
                      ? Text(post.userDisplayName?.substring(0, 1).toUpperCase() ?? 'U')
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
                      onSelected: (value){
                        if (value == 'edit') {
                          _navigateToEditPost(post);
                        }else if (value == 'delete'){
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
                padding: const EdgeInsets.only(bottom: 8.0), // Add some space if image follows
                child: Text(
                  post.content!,
                  style: const TextStyle(fontSize: 15),
                ),
              ),

            // --- Display Image ---
            if (post.imageUrl != null && post.imageUrl!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: ClipRRect( // To give rounded corners to the image
                  borderRadius: BorderRadius.circular(8.0),
                  child: Image.network(
                    post.imageUrl!,
                    width: double.infinity,
                    fit: BoxFit.cover, // Or BoxFit.contain, depending on desired look
                    loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
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
                    errorBuilder: (BuildContext context, Object exception, StackTrace? stackTrace) {
                      return Container(
                        height: 150, // Give some height to the error placeholder
                        color: Colors.grey[200],
                        child: const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 50)),
                      );
                    },
                  ),
                ),
              ),
            // --- End Display Image ---

            const SizedBox(height: 10),
            Text(
              'Posted: ${post.createdAt.toLocal().toString().substring(0, 16)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),

            const SizedBox(height: 8),
            Divider(),
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                        icon: Icon(
                          post.currentUserHasLiked ? Icons.favorite : Icons.favorite_border,
                          color: post.currentUserHasLiked ? Colors.red : null,
                          size: 20,
                        ),
                        label: Text(
                          'Like',
                          style: TextStyle(
                            color: post.currentUserHasLiked ? Colors.red : null,
                            ),
                          ),
                        onPressed: () {
                           _toggleLike(post);
                        },
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
      MaterialPageRoute(
          builder: (context) => EditPostScreen(postToEdit: post),
      ),
    ).then((result) {
      if (result == true && mounted){
        _fetchPosts();
      }
    });
  }

  Future<void> _confirmDeletePost(UserPost post) async {
    final confirm = await showDialog<bool>(context: context, builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Confirm Deletion'),
        content: const Text('Are you sure you want to delete this post?'),
        actions: <Widget>[
          TextButton(
            child: const Text('Cancel'),
            onPressed: (){
              Navigator.pop(context, false);
            },
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
            onPressed: (){
              Navigator.pop(context, true);
            },
          ),
        ],
      );
    });

    if (confirm == true && mounted) {
      setState(() {
        _isLoading = true;
      });
      try {
        if (post.imageUrl != null && post.imageUrl!.isNotEmpty) {
          final imagePath = extractPathFromUrl(post.imageUrl!);
          if (imagePath != null) {
            try {
              await _supabase.storage.from('post_images').remove([imagePath]);
            } catch (storageError){
              print('Error removing image from storage: $storageError(Continuing with post deletion)');
            }
          }
        }
        await _supabase.from('posts').delete().eq('id', post.id);

        if (mounted) {
          _fetchPosts();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post deleted')));
        }
      } on PostgrestException catch (e){
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DB Error deleting post: ${e.message}')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting post: $e')));
        }
      } finally {
        if (mounted && _isLoading){
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("User Feed"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage!, textAlign: TextAlign.center, style: TextStyle(color: Colors.red[700], fontSize: 16)),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _fetchPosts, child: const Text('Try Again'))
            ],
          ),
        ),
      )
          : _posts.isEmpty
          ? const Center(
        child: Text(
          'No posts yet. Be the first to share something!',
          style: TextStyle(fontSize: 16, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      )
          : RefreshIndicator(
        onRefresh: _fetchPosts,
        child: ListView.builder(
          itemCount: _posts.length,
          itemBuilder: (context, index) {
            final post = _posts[index];
            return _buildPostItem(post);
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToCreatePost,
        tooltip: 'Create Post',
        child: const Icon(Icons.add_comment_outlined),
      ),
    );
  }
}

