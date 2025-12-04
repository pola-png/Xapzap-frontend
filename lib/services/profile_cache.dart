import '../models/post.dart';

class ProfileCacheEntry {
  final Map<String, dynamic>? profile;
  final List<Post> posts;
  final Map<String, List<String>> mediaByPostId;
  final int postsCount;
  final int followersCount;
  final int followingCount;
  final DateTime? joinedAt;

  ProfileCacheEntry({
    required this.profile,
    required this.posts,
    required this.mediaByPostId,
    required this.postsCount,
    required this.followersCount,
    required this.followingCount,
    required this.joinedAt,
  });
}

class ProfileCache {
  static final Map<String, ProfileCacheEntry> _entries = <String, ProfileCacheEntry>{};

  static ProfileCacheEntry? get(String userId) => _entries[userId];

  static void set(String userId, ProfileCacheEntry entry) {
    _entries[userId] = entry;
  }

  static void clear(String userId) {
    _entries.remove(userId);
  }
}

