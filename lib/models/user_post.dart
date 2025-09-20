// lib/models/user_post.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class UserPost {
  final String id; // Post ID
  final String userId; // ID of the user who made the post
  final String? content;
  final String? imageUrl; // We'll add this later if needed
  final DateTime createdAt;

  // Information about the user who made the post
  final String? userDisplayName;
  final String? userAvatarUrl;

  // reactions
  final int likeCount;
  final bool currentUserHasLiked;

  UserPost({
    required this.id,
    required this.userId,
    this.content,
    this.imageUrl,
    required this.createdAt,
    this.userDisplayName,
    this.userAvatarUrl,
    this.likeCount = 0,
    this.currentUserHasLiked = false,
  });

  factory UserPost.fromMap(Map<String, dynamic> map) {

    final authorData = map['author'] as Map<String, dynamic>?;

    int likes = 0;
    if (map['like_count'] is int) {
      likes = map['like_count'];
    } else if (map['like_count'] is List && (map['like_count'] as List).isNotEmpty) {
      final likeData = (map['like_count'] as List).first as Map<String, dynamic>?;
      if (likeData != null && likeData['count'] is int){
        likes = likeData['count'];
      }
    }

    bool userLiked = false;
    if (map['current_user_has_liked'] is bool) {
      userLiked = map['current_user_has_liked'];
    }

    return UserPost(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      content: map['content'] as String?,
      imageUrl: map['image_url'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      userDisplayName: authorData?['display_name'] as String?,
      userAvatarUrl: authorData?['avatar_url'] as String?,
      likeCount: likes,
      currentUserHasLiked: userLiked,
    );
  }

  UserPost copyWith({
    int? likeCount,
    bool? currentUserHasLiked,
  }) {
    return UserPost(
      id: id,
      userId: userId,
      content: content,
      imageUrl: imageUrl,
      createdAt: createdAt,
      userDisplayName: userDisplayName,
      userAvatarUrl: userAvatarUrl,
      likeCount: likeCount ?? this.likeCount,
      currentUserHasLiked: currentUserHasLiked ?? this.currentUserHasLiked,
    );
  }
}
