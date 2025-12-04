import 'package:appwrite/models.dart' as aw;

import '../models/post.dart';
import '../services/appwrite_service.dart';
import '../services/storage_service.dart';
import '../services/feed_cache.dart';
import '../services/avatar_cache.dart';

/// Preloads the home feed in the background so that
/// the HomeScreen can render instantly using FeedCache.
class FeedPrefetcher {
  static bool _started = false;

  static Future<void> preloadHomeFeeds() async {
    if (_started) return;
    _started = true;

    try {
      final user = await AppwriteService.getCurrentUser();
      final followingIds =
          user != null ? await AppwriteService.getFollowingUserIds(user.$id) : <String>[];

      await Future.wait([
        _preloadForYou(),
        if (followingIds.isNotEmpty) _preloadFollowing(followingIds),
      ]);
    } catch (_) {
      // Best-effort only; HomeScreen will still load feeds normally.
    }
  }

  static Future<void> _preloadForYou() async {
    if (FeedCache.hasForYou) return;

    final aw.RowList docsList =
        await AppwriteService.fetchPosts(limit: 40);
      final List<aw.Row> docs = docsList.rows;
    if (docs.isEmpty) return;

    final posts = <Post>[];
    final mediaByPostId = <String, List<String>>{};
    final authorByPostId = <String, String>{};

      for (final d in docs) {
        final data = d.data;
      final List<String> rawMedia = data['mediaUrls'] is List
          ? (data['mediaUrls'] as List).map((item) => item.toString()).toList()
          : <String>[];
      authorByPostId[d.$id] = data['userId'] as String? ?? '';
      final kind = (data['postType'] ?? data['type'] ?? data['category']) as String?;
      final title = data['title'] as String?;
      final thumbnailUrl = data['thumbnailUrl'] as String?;
      final kindLower = (kind ?? '').toLowerCase();
      final bool isVideoKind = kindLower.contains('video') || kindLower.contains('reel');

      String? videoUrl;
      String? firstImage;
      List<String> mediaForUi;

      if (isVideoKind && rawMedia.isNotEmpty) {
        final first = rawMedia.first;
        videoUrl = (first.startsWith('http://') || first.startsWith('https://'))
            ? first
            : await WasabiService.getSignedUrl(first);
        firstImage = thumbnailUrl?.isNotEmpty == true
            ? (thumbnailUrl!.startsWith('http')
                ? thumbnailUrl
                : await WasabiService.getSignedUrl(thumbnailUrl))
            : (rawMedia.length > 1 ? rawMedia[1] : null);
        mediaForUi = firstImage != null ? <String>[firstImage] : <String>[];
      } else {
        firstImage = thumbnailUrl?.isNotEmpty == true
            ? (thumbnailUrl!.startsWith('http')
                ? thumbnailUrl
                : await WasabiService.getSignedUrl(thumbnailUrl))
            : (rawMedia.isNotEmpty ? rawMedia.first : null);
        mediaForUi = rawMedia;
      }

      mediaByPostId[d.$id] = mediaForUi;

      // Warm avatar cache so feed avatars are instant.
      final userId = data['userId'] as String? ?? '';
      String avatar = data['userAvatar'] as String? ?? '';
      if (userId.isNotEmpty && avatar.isNotEmpty) {
        if (!avatar.startsWith('http')) {
          try {
            avatar = await WasabiService.getSignedUrl(avatar);
          } catch (_) {}
        }
        await AvatarCache.setForUserId(userId, avatar);
      }
      posts.add(
        Post(
          id: d.$id,
          username: data['username'] as String? ?? 'No Name',
          userAvatar: data['userAvatar'] as String? ?? '',
          content: data['content'] as String? ?? '',
          textBgColor: data['textBgColor'] as int?,
          timestamp: DateTime.tryParse(d.$createdAt) ??
              (data['createdAt'] != null
                  ? DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now()
                  : DateTime.now()),
          likes: data['likes'] as int? ?? 0,
          comments: data['comments'] as int? ?? 0,
          reposts: data['reposts'] as int? ?? 0,
          impressions: data['impressions'] as int? ?? 0,
          views: data['views'] as int? ?? 0,
          imageUrl: firstImage,
          videoUrl: videoUrl,
          kind: kind,
          title: title,
          thumbnailUrl: thumbnailUrl,
        ),
      );
    }

    FeedCache.forYouPosts = posts;
    FeedCache.mediaByPostId = mediaByPostId;
    FeedCache.authorByPostId = authorByPostId;
    FeedCache.forYouCursor = docs.last.$id;
  }

  static Future<void> _preloadFollowing(List<String> followingIds) async {
    if (FeedCache.hasFollowing) return;

    final aw.RowList docsList = await AppwriteService.fetchPostsByUserIds(
      followingIds,
      limit: 40,
    );
    final List<aw.Row> docs = docsList.rows;
    if (docs.isEmpty) return;

    final posts = <Post>[];
    final mediaByPostId = FeedCache.mediaByPostId;
    final authorByPostId = FeedCache.authorByPostId;

    for (final d in docs) {
      final data = d.data;
      final List<String> rawMedia = data['mediaUrls'] is List
          ? (data['mediaUrls'] as List).map((item) => item.toString()).toList()
          : <String>[];
      authorByPostId[d.$id] = data['userId'] as String? ?? '';
      final kind = (data['postType'] ?? data['type'] ?? data['category']) as String?;
      final title = data['title'] as String?;
      final thumbnailUrl = data['thumbnailUrl'] as String?;
      final kindLower = (kind ?? '').toLowerCase();
      final bool isVideoKind = kindLower.contains('video') || kindLower.contains('reel');

      String? videoUrl;
      String? firstImage;
      List<String> mediaForUi;

      if (isVideoKind && rawMedia.isNotEmpty) {
        final first = rawMedia.first;
        videoUrl = (first.startsWith('http://') || first.startsWith('https://'))
            ? first
            : await WasabiService.getSignedUrl(first);
        firstImage = thumbnailUrl?.isNotEmpty == true
            ? (thumbnailUrl!.startsWith('http')
                ? thumbnailUrl
                : await WasabiService.getSignedUrl(thumbnailUrl))
            : (rawMedia.length > 1 ? rawMedia[1] : null);
        mediaForUi = firstImage != null ? <String>[firstImage] : <String>[];
      } else {
        firstImage = thumbnailUrl?.isNotEmpty == true
            ? (thumbnailUrl!.startsWith('http')
                ? thumbnailUrl
                : await WasabiService.getSignedUrl(thumbnailUrl))
            : (rawMedia.isNotEmpty ? rawMedia.first : null);
        mediaForUi = rawMedia;
      }

      mediaByPostId[d.$id] = mediaForUi;

      // Warm avatar cache for following feed as well.
      final userId = data['userId'] as String? ?? '';
      String avatar = data['userAvatar'] as String? ?? '';
      if (userId.isNotEmpty && avatar.isNotEmpty) {
        if (!avatar.startsWith('http')) {
          try {
            avatar = await WasabiService.getSignedUrl(avatar);
          } catch (_) {}
        }
        await AvatarCache.setForUserId(userId, avatar);
      }
      posts.add(
        Post(
          id: d.$id,
          username: data['username'] as String? ?? 'No Name',
          userAvatar: data['userAvatar'] as String? ?? '',
          content: data['content'] as String? ?? '',
          textBgColor: data['textBgColor'] as int?,
          timestamp: DateTime.tryParse(d.$createdAt) ??
              (data['createdAt'] != null
                  ? DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now()
                  : DateTime.now()),
          likes: data['likes'] as int? ?? 0,
          comments: data['comments'] as int? ?? 0,
          reposts: data['reposts'] as int? ?? 0,
          impressions: data['impressions'] as int? ?? 0,
          views: data['views'] as int? ?? 0,
          imageUrl: firstImage,
          videoUrl: videoUrl,
          kind: kind,
          title: title,
          thumbnailUrl: thumbnailUrl,
        ),
      );
    }

    FeedCache.followingPosts = posts;
    FeedCache.mediaByPostId = mediaByPostId;
    FeedCache.authorByPostId = authorByPostId;
    FeedCache.followingCursor = docs.last.$id;
  }
}
