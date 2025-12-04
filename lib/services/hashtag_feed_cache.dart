import '../models/post.dart';

/// Simple in-memory cache for hashtag feeds so that navigating
/// between screens does not cause full reloads every time.
class HashtagFeedCacheEntry {
  final List<Post> posts;
  final Map<String, List<String>> mediaByPostId;
  final Map<String, String> authorByPostId;
  final String? cursor;

  HashtagFeedCacheEntry({
    required this.posts,
    required this.mediaByPostId,
    required this.authorByPostId,
    required this.cursor,
  });
}

class HashtagFeedCache {
  static final Map<String, HashtagFeedCacheEntry> _entries =
      <String, HashtagFeedCacheEntry>{};

  static HashtagFeedCacheEntry? get(String tag) => _entries[tag];

  static void set(String tag, HashtagFeedCacheEntry entry) {
    _entries[tag] = entry;
  }

  static void clear(String tag) {
    _entries.remove(tag);
  }
}

