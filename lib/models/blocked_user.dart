class BlockedUserInfo {
  final String userId;
  final String? displayName;
  final String? email;
  final String? avatarUrl; // Optional: if you want to display avatars

  BlockedUserInfo({
    required this.userId,
    this.displayName,
    this.email,
    this.avatarUrl,
  });

  // Factory constructor to create an instance from a map (e.g., Supabase row)
  factory BlockedUserInfo.fromMap(Map<String, dynamic> map) {
    return BlockedUserInfo(
      userId: map['id'] as String, // From the joined 'users' table
      displayName: map['display_name'] as String?,
      email: map['email'] as String?,
      avatarUrl: map['avatar_url'] as String?,
    );
  }
}