// lib/ui/screens/news_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user_post.dart'; // Adjust path if your model is elsewhere
// We'll create create_post_screen.dart in the next step
import 'create_post.dart';

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

  // Placeholder for the current user's ID.
  // In a real app, you'd get this after the user logs in.
  // For testing, you can hardcode a UUID of a user that exists in your public.users table.
  // Example: String? currentFixedUserId = 'your-test-user-uuid-from-public-users-table';
  String? get currentUserId {
    // **IMPORTANT**: Replace this with your actual way of getting the logged-in user's ID
    // For now, let's assume you have a way or will hardcode for testing.
    // If you don't have auth yet, and want anyone to post, this logic will need to change
    // or you'll need to pass null or handle anonymous posts.
    // return currentFixedUserId;

    // If using Supabase Auth (which you said you are not, but for others' reference):
    // return _supabase.auth.currentUser?.id;

    // For now, if you don't have a way to get the current user,
    // post creation will be disabled or will need a fixed ID.
    // For fetching, it doesn't matter unless RLS blocks it.
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
      final response = await _supabase
          .from('posts')
          .select('''
              id,
              user_id,
              content,
              image_url,
              created_at,
              author:users ( 
                display_name,
                avatar_url
              )
          ''')
      // This join works because posts.user_id has an FK to users.id
          .order('created_at', ascending: false)
          .limit(20);

      if (!mounted) return;

      _posts = response.map((item) => UserPost.fromMap(item)).toList();

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

  Widget _buildPostItem(UserPost post) {
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
                Text(
                  post.userDisplayName ?? 'Anonymous User',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
          ],
        ),
      ),
    );
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

