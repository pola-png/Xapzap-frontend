import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as aw;
import '../services/appwrite_service.dart';
import '../services/storage_service.dart';
import '../services/hashtag_feed_cache.dart';
import '../models/post.dart';
import '../widgets/post_card.dart';

class HashtagFeedScreen extends StatefulWidget {
  final String tag;

  const HashtagFeedScreen({super.key, required this.tag});

  @override
  State<HashtagFeedScreen> createState() => _HashtagFeedScreenState();
}

class _HashtagFeedScreenState extends State<HashtagFeedScreen> {
  final List<Post> _posts = [];
  final Map<String, List<String>> _mediaByPostId = {};
  final Map<String, String> _authorByPostId = {};
  bool _isLoading = false;
  String? _cursor;

  @override
  void initState() {
    super.initState();
    // Restore from in-memory cache if available for this hashtag,
    // so navigating back does not re-fetch everything. Reactions
    // (likes, comments, views) still update live via realtime.
    final cached = HashtagFeedCache.get(widget.tag);
    if (cached != null) {
      _posts
        ..clear()
        ..addAll(cached.posts);
      _mediaByPostId
        ..clear()
        ..addAll(cached.mediaByPostId);
      _authorByPostId
        ..clear()
        ..addAll(cached.authorByPostId);
      _cursor = cached.cursor;
    } else {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final aw.RowList list =
          await AppwriteService.searchPostsByHashtag(widget.tag, limit: 20, cursorId: _cursor);
      final rows = list.rows;
      final mapped = <Post>[];
      for (final d in rows) {
        final data = d.data;
        final List<String> rawMedia = data['mediaUrls'] is List
            ? (data['mediaUrls'] as List).map((e) => e.toString()).toList()
            : <String>[];
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

        _mediaByPostId[d.$id] = mediaForUi;
        _authorByPostId[d.$id] = data['userId'] as String? ?? '';
        mapped.add(
          Post(
            id: d.$id,
            username: data['username'] as String? ?? 'No Name',
            userAvatar: data['userAvatar'] as String? ?? '',
            content: data['content'] as String? ?? '',
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
      setState(() {
        _posts.addAll(mapped);
        if (rows.isNotEmpty) {
          _cursor = rows.last.$id;
        }
        // Persist hashtag feed cache for this tag.
        HashtagFeedCache.set(
          widget.tag,
          HashtagFeedCacheEntry(
            posts: List<Post>.from(_posts),
            mediaByPostId: Map<String, List<String>>.from(_mediaByPostId),
            authorByPostId: Map<String, String>.from(_authorByPostId),
            cursor: _cursor,
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('#${widget.tag}', style: TextStyle(color: theme.colorScheme.onSurface)),
        backgroundColor: theme.colorScheme.surface,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {
            _posts.clear();
            _mediaByPostId.clear();
            _cursor = null;
          });
          HashtagFeedCache.clear(widget.tag);
          await _loadMore();
        },
        child: ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: _posts.length + (_isLoading ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _posts.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final post = _posts[index];
            return PostCard(
              post: post,
              isGuest: false,
              mediaUrls: _mediaByPostId[post.id],
              authorId: _authorByPostId[post.id],
              onDeleted: () {
                setState(() {
                  _posts.removeWhere((p) => p.id == post.id);
                });
              },
              onOpenPost: () {
                // Reuse HomeScreen navigation for video vs text posts.
                // For simplicity, let PostCard's own onOpenPost handle it if set.
              },
            );
          },
        ),
      ),
    );
  }
}
