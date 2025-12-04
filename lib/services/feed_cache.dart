import '../models/post.dart';

/// Simple in-memory cache for home feeds so that navigating
/// between screens does not cause full reloads every time.
class FeedCache {
  static List<Post> forYouPosts = <Post>[];
  static List<Post> followingPosts = <Post>[];
  static Map<String, List<String>> mediaByPostId = <String, List<String>>{};
  static Map<String, String> authorByPostId = <String, String>{};
  static String? forYouCursor;
  static String? followingCursor;

  static bool get hasForYou => forYouPosts.isNotEmpty;
  static bool get hasFollowing => followingPosts.isNotEmpty;

  static void clearForYou() {
    forYouPosts = <Post>[];
    forYouCursor = null;
  }

  static void clearFollowing() {
    followingPosts = <Post>[];
    followingCursor = null;
  }
}

