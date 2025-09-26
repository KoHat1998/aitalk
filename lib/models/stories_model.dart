class UserStoryGroup {
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final List<StoryItem> stories;

  UserStoryGroup({
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.stories,
  });
}

class StoryItem {
  final String id;
  final String mediaUrl;
  final String mediaType;
  final String? caption;
  final DateTime createdAt;

  StoryItem({
    required this.id,
    required this.mediaUrl,
    required this.mediaType,
    this.caption,
    required this.createdAt,
  });

  factory StoryItem.fromMap(Map<String, dynamic> map) {
    return StoryItem(
      id: map['id'] as String,
      mediaUrl: map['media_url'] as String,
      mediaType: map['media_type'] as String,
      caption: map['caption'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}