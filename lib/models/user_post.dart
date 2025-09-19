// lib/models/user_post.dart
class UserPost {
  final String id; // Post ID
  final String userId; // ID of the user who made the post
  final String? content;
  final String? imageUrl; // We'll add this later if needed
  final DateTime createdAt;

  // Information about the user who made the post
  final String? userDisplayName;
  final String? userAvatarUrl;

  UserPost({
    required this.id,
    required this.userId,
    this.content,
    this.imageUrl,
    required this.createdAt,
    this.userDisplayName,
    this.userAvatarUrl,
  });

  // Factory constructor to create a UserPost from a Supabase map
  factory UserPost.fromMap(Map<String, dynamic> map) {
    // The 'map' will contain fields from 'posts' table
    // and potentially nested data from 'users' table if we do a join.

    // Extract author data if it was joined and aliased as 'author'
    final authorData = map['author'] as Map<String, dynamic>?;

    return UserPost(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      content: map['content'] as String?,
      imageUrl: map['image_url'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      userDisplayName: authorData?['display_name'] as String?,
      userAvatarUrl: authorData?['avatar_url'] as String?,
    );
  }
}
