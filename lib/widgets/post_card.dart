import 'dart:async';
import 'dart:math' as math;

import 'package:appwrite/appwrite.dart' show RealtimeSubscription;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../utils/share_utils.dart';

import '../models/post.dart';
import '../screens/comment_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/edit_post_screen.dart';
import '../services/appwrite_service.dart';
import '../services/storage_service.dart';
import '../services/avatar_cache.dart';
import '../screens/hashtag_feed_screen.dart';
import '../screens/boost_post_screen.dart';
import 'taggable_text.dart';

class PostCard extends StatefulWidget {
  final Post post;
  final bool isGuest;
  final VoidCallback? onGuestAction;
  final List<String>? mediaUrls;
  final String? authorId;
  final VoidCallback? onOpenPost;
  final VoidCallback? onDeleted;
  final bool isDetail;
  final bool trackImpressions;
  final bool showViewsLabel;
  final int? videoDescriptionMaxLines;
  final VoidCallback? onVideoDescriptionTap;
  final bool showVideoMeta;
  final bool showReelBadge;

  const PostCard({
    super.key,
    required this.post,
    this.isGuest = false,
    this.onGuestAction,
    this.mediaUrls,
    this.authorId,
    this.onOpenPost,
    this.onDeleted,
    this.isDetail = false,
    this.trackImpressions = true,
    this.showViewsLabel = false,
    this.showVideoMeta = true,
    this.videoDescriptionMaxLines,
    this.onVideoDescriptionTap,
    this.showReelBadge = false,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  // Cache signed URLs for avatar keys within a single run.
  static final Map<String, String?> _avatarSignedCacheByKey =
      <String, String?>{};
  // Cache display names so we can show the up-to-date
  // profile displayName instead of the stale username
  // snapshot stored on each post row.
  static final Map<String, String?> _displayNameByUserId = <String, String?>{};
  static final Map<String, String?> _displayNameByUsername =
      <String, String?>{};
  // Cache like state per post so UI doesn't flicker while remote state loads.
  static final Map<String, bool> _likeCache = <String, bool>{};

  bool _isLiked = false;
  int _likeCount = 0;
  int _commentCount = 0;
  int _repostCount = 0;
  int _impressionCount = 0;
  int _shareCount = 0;
  bool _isSaved = false;
  int _currentMediaIndex = 0;
  bool _hasReposted = false;
  bool _followLoaded = false;
  bool _likeManuallySet = false;
  String _displayName = '';

  String? _currentUserId;
  bool _isFollowing = false;
  RealtimeSubscription? _postSub;
  final Map<String, String> _signedCache = {};
  PageController? _pageController;

  @override
  void initState() {
    super.initState();
    _isLiked = _likeCache[widget.post.id] ?? widget.post.isLiked;
    _likeCount = widget.post.likes;
    _commentCount = widget.post.comments;
    _repostCount = widget.post.reposts;
    _impressionCount = widget.post.impressions;

    _initAvatar();
    _initUserAndFollow();
    _subscribeRealtime();
    _prefetchInitialMedia();
    _ensureDisplayName();
    // Count an impression for this post when the card is created (optional).
    if (widget.trackImpressions) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _impressionCount++);
        AppwriteService.incrementPostImpressions(widget.post.id, 1);
      });
    }
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authorId != widget.authorId ||
        oldWidget.post.username != widget.post.username ||
        oldWidget.post.userAvatar != widget.post.userAvatar) {
      _initAvatar(reset: true);
      _ensureDisplayName();
    }
    if (oldWidget.post.id != widget.post.id) {
      // New post entirely: sync fresh state.
      _likeManuallySet = false;
      _isLiked = _likeCache[widget.post.id] ?? widget.post.isLiked;
      _likeCount = widget.post.likes;
      _commentCount = widget.post.comments;
      _repostCount = widget.post.reposts;
      _impressionCount = widget.post.impressions;
      _isSaved = widget.post.isSaved;
      _hasReposted = widget.post.isReposted;
    } else {
      // Same post instance refreshed; do not wipe a like that was already set locally.
      if (!_isLiked && widget.post.isLiked) {
        _isLiked = true;
      }
      // Keep counts in sync when server values increase.
      if (widget.post.likes > _likeCount) _likeCount = widget.post.likes;
      if (widget.post.comments > _commentCount)
        _commentCount = widget.post.comments;
      if (widget.post.reposts > _repostCount)
        _repostCount = widget.post.reposts;
      if (widget.post.impressions > _impressionCount)
        _impressionCount = widget.post.impressions;
      if (!_isSaved && widget.post.isSaved) _isSaved = true;
      if (!_hasReposted && widget.post.isReposted) _hasReposted = true;
    }
  }

  String? _avatarUrl;
  Future<void>? _displayNameFuture;

  void _initAvatar({bool reset = false}) {
    if (reset) {
      _avatarUrl = null;
    }
    // If post already carries a full avatar URL, use it directly.
    final rawAvatar = widget.post.userAvatar;
    if (rawAvatar.isNotEmpty &&
        (rawAvatar.startsWith('http://') || rawAvatar.startsWith('https://'))) {
      _avatarUrl = rawAvatar;
      return;
    }

    // Try persistent cache by userId or username.
    String? userId = widget.authorId;
    final handle = widget.post.username
        .replaceAll('@', '')
        .trim()
        .toLowerCase();

    if (userId != null && userId.isNotEmpty) {
      final cached = AvatarCache.getForUserId(userId);
      if (cached != null) {
        _avatarUrl = cached;
        return;
      }
    }
    if ((userId == null || userId.isEmpty) && handle.isNotEmpty) {
      final cachedByName = AvatarCache.getForUsername(handle);
      if (cachedByName != null) {
        _avatarUrl = cachedByName;
        return;
      }
    }

    // Fallback: async resolve via profile lookups.
    _loadAvatarFromNetwork();
  }

  Future<void> _ensureDisplayName() async {
    // Use cached display name if present.
    final cached = _getCachedDisplayName();
    if (cached != null && cached.isNotEmpty) {
      _displayName = cached;
      return;
    }
    // Fetch from profile table using authorId if available.
    final userId = widget.authorId;
    if (userId == null || userId.isEmpty) return;
    _displayNameFuture ??= _fetchDisplayName(userId);
    await _displayNameFuture;
  }

  Future<void> _fetchDisplayName(String userId) async {
    try {
      final prof = await AppwriteService.getProfileByUserId(userId);
      final dn = (prof?.data['displayName'] as String?)?.trim();
      if (dn != null && dn.isNotEmpty) {
        _displayNameByUserId[userId] = dn;
        final handle = widget.post.username
            .replaceAll('@', '')
            .trim()
            .toLowerCase();
        if (handle.isNotEmpty) {
          _displayNameByUsername[handle] = dn;
        }
        if (mounted) {
          setState(() {
            _displayName = dn;
          });
        } else {
          _displayName = dn;
        }
      }
    } catch (_) {
      // ignore failures; fallback remains empty
    }
  }

  Future<void> _loadAvatarFromNetwork() async {
    final url = await _getAvatarUrl();
    if (!mounted) return;
    if (url == null || url.isEmpty) return;
    setState(() {
      _avatarUrl = url;
    });
  }

  Future<void> _initUserAndFollow() async {
    final me = await AppwriteService.getCurrentUser();
    if (!mounted) return;
    setState(() => _currentUserId = me?.$id);
    if (me != null && widget.authorId != null && widget.authorId != me.$id) {
      final f = await AppwriteService.isFollowing(me.$id, widget.authorId!);
      if (!mounted) return;
      setState(() {
        _isFollowing = f;
        _followLoaded = true;
      });
    } else {
      // No follow relationship possible (guest/self/unknown author).
      _followLoaded = true;
    }
    // Load initial like status per user
    if (me != null) {
      final liked = await AppwriteService.isPostLikedBy(me.$id, widget.post.id);
      final saved = await AppwriteService.isPostSavedBy(me.$id, widget.post.id);
      final reposted = await AppwriteService.isPostRepostedBy(
        me.$id,
        widget.post.id,
      );
      if (!mounted) return;
      if (!_likeManuallySet) {
        setState(() {
          _isLiked = liked;
          _isSaved = saved;
          _hasReposted = reposted;
          _likeCache[widget.post.id] = _isLiked;
        });
      } else {
        // Still refresh saved/reposted even if like was manually set.
        setState(() {
          _isSaved = saved;
          _hasReposted = reposted;
        });
      }
    }
  }

  void _subscribeRealtime() {
    final channel =
        'databases.${AppwriteService.databaseId}.collections.${AppwriteService.postsCollectionId}.documents.${widget.post.id}';
    try {
      _postSub = AppwriteService.realtime.subscribe([channel]);
      _postSub?.stream.listen((event) {
        final payload = event.payload;
        if (payload.isNotEmpty) {
          final likes = payload['likes'];
          final comments = payload['comments'];
          final reposts = payload['reposts'];
          final impressions = payload['impressions'];
          final shares = payload['shares'];
          setState(() {
            int? parsedLikes;
            int? parsedComments;
            int? parsedReposts;
            int? parsedImpressions;
            int? parsedShares;

            if (likes is int) {
              parsedLikes = likes;
            } else if (likes is String) {
              parsedLikes = int.tryParse(likes);
            }
            if (comments is int) {
              parsedComments = comments;
            } else if (comments is String) {
              parsedComments = int.tryParse(comments);
            }
            if (reposts is int) {
              parsedReposts = reposts;
            } else if (reposts is String) {
              parsedReposts = int.tryParse(reposts);
            }
            if (impressions is int) {
              parsedImpressions = impressions;
            } else if (impressions is String) {
              parsedImpressions = int.tryParse(impressions);
            }
            if (shares is int) {
              parsedShares = shares;
            } else if (shares is String) {
              parsedShares = int.tryParse(shares);
            }

            // Only move counts forward to preserve instant UI updates.
            if (parsedLikes != null && parsedLikes >= _likeCount) {
              _likeCount = parsedLikes;
            }
            if (parsedComments != null && parsedComments >= _commentCount) {
              _commentCount = parsedComments;
            }
            if (parsedReposts != null && parsedReposts >= _repostCount) {
              _repostCount = parsedReposts;
            }
            if (parsedImpressions != null &&
                parsedImpressions >= _impressionCount) {
              _impressionCount = parsedImpressions;
            }
            if (parsedShares != null && parsedShares >= _shareCount) {
              _shareCount = parsedShares;
            }
          });
        }
      });
    } catch (_) {}
  }

  void _prefetchInitialMedia() {
    final urls =
        widget.mediaUrls ??
        (widget.post.imageUrl != null ? [widget.post.imageUrl!] : <String>[]);
    if (urls.isNotEmpty) {
      _resolveSigned(urls.first).then((u) {
        if (u != null) _precache(u);
      });
      if (urls.length > 1) {
        _resolveSigned(urls[1]).then((u) {
          if (u != null) _precache(u);
        });
      }
    }
  }

  @override
  void dispose() {
    _postSub?.close();
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final kindLower = (widget.post.kind ?? '').toLowerCase();
    final isVideoPost =
        kindLower.contains('video') ||
        kindLower.contains('reel') ||
        kindLower.contains('short');
    // Faint dark gap between posts, adapt to theme.
    final gapColor = isDark ? Colors.black : Colors.black.withOpacity(0.03);

    final card = Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (widget.post.content.isNotEmpty && !isVideoPost)
            _buildTextContent(),
          // For video/reel posts, only show the media/placeholder in feed cards,
          // not inside detail screens where the dedicated player is used.
          if ((widget.mediaUrls?.isNotEmpty ?? false) ||
              widget.post.imageUrl != null ||
              (isVideoPost && !widget.isDetail))
            _buildMediaContent(),
          if (isVideoPost && widget.showVideoMeta) _buildVideoMeta(),
          _buildActions(),
        ],
      ),
    );

    if (widget.isDetail) {
      // In detail view, render the card without outer gap so comments can sit flush below.
      return card;
    }

    return Container(
      color: gapColor,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: card,
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.post.sourceUsername != null &&
              widget.post.sourceUsername!.isNotEmpty &&
              widget.post.sourceUsername != widget.post.username)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${widget.post.sourceUsername} reposted',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          Row(
            children: [
              GestureDetector(onTap: _openAuthorProfile, child: _buildAvatar()),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _openAuthorProfile,
                  behavior: HitTestBehavior.translucent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayName.isNotEmpty
                            ? _displayName
                            : (_getCachedDisplayName() ?? ''),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: theme.brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black,
                        ),
                      ),
                      Text(
                        _formatTimestamp(widget.post.timestamp),
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.showReelBadge)
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9333EA).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Reels',
                    style: TextStyle(
                      color: Color(0xFF9333EA),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (!widget.isGuest &&
                  widget.authorId != null &&
                  _currentUserId != null &&
                  widget.authorId != _currentUserId &&
                  _followLoaded &&
                  !_isFollowing)
                ElevatedButton(
                  onPressed: _toggleFollow,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    backgroundColor: _isFollowing
                        ? Colors.red.shade50
                        : const Color(0xFFEF4444),
                    foregroundColor: _isFollowing
                        ? const Color(0xFFB91C1C)
                        : Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: Text(
                    _isFollowing ? 'Following' : 'Follow',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              IconButton(
                icon: Icon(
                  LucideIcons.moreHorizontal,
                  color: theme.iconTheme.color,
                ),
                onPressed: () => _showReportMenu(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final avatarUrl = _avatarUrl;
    if (avatarUrl == null || avatarUrl.isEmpty) {
      return CircleAvatar(
        radius: 30,
        backgroundColor: Colors.grey[200],
        child: const Icon(Icons.person, color: Colors.grey),
      );
    }
    return CircleAvatar(
      radius: 30,
      backgroundColor: Colors.grey[200],
      backgroundImage: NetworkImage(avatarUrl),
    );
  }

  Future<String?> _getAvatarUrl() async {
    // If post already has a userAvatar key, resolve/sign it once
    // and cache by that key so multiple cards don't re-sign it.
    if (widget.post.userAvatar.isNotEmpty) {
      final rawKey = widget.post.userAvatar;
      final cachedSigned = _avatarSignedCacheByKey[rawKey];
      if (cachedSigned != null) {
        return cachedSigned;
      }
      final resolved = await _resolveSigned(rawKey);
      if (resolved != null) {
        _avatarSignedCacheByKey[rawKey] = resolved;
      }
      return resolved;
    }

    // Prefer caching by userId; fall back to username handle.
    String? userId = widget.authorId;
    final handle = widget.post.username
        .replaceAll('@', '')
        .trim()
        .toLowerCase();

    if (userId != null && userId.isNotEmpty) {
      final cached = AvatarCache.getForUserId(userId);
      if (cached != null) return cached;
    }
    if ((userId == null || userId.isEmpty) && handle.isNotEmpty) {
      final cachedByName = AvatarCache.getForUsername(handle);
      if (cachedByName != null) return cachedByName;
    }

    String? avatar;

    try {
      // 1) If we don't know userId, try resolving by @username.
      if ((userId == null || userId.isEmpty) && handle.isNotEmpty) {
        final prof = await AppwriteService.getProfileByUsername(handle);
        if (prof != null) {
          userId = prof.data['userId'] as String? ?? prof.$id;
          avatar = prof.data['avatarUrl'] as String?;
          final dn = (prof.data['displayName'] as String?)?.trim();
          if (dn != null && dn.isNotEmpty) {
            _displayNameByUserId[userId] = dn;
            _displayNameByUsername[handle] = dn;
          }
        }
      }

      // 2) If still no avatar, load profile by userId.
      if ((avatar == null || avatar.isEmpty) &&
          userId != null &&
          userId.isNotEmpty) {
        final prof = await AppwriteService.getProfileByUserId(userId);
        avatar = prof?.data['avatarUrl'] as String?;
        final dn = (prof?.data['displayName'] as String?)?.trim();
        if (dn != null && dn.isNotEmpty) {
          _displayNameByUserId[userId] = dn;
          if (handle.isNotEmpty) {
            _displayNameByUsername[handle] = dn;
          }
        }
      }
    } catch (_) {
      // Ignore errors and fall back to placeholder avatar.
    }

    // Cache negative result so we don't keep hitting the backend.
    if (avatar == null || avatar.isEmpty) {
      if (userId != null && userId.isNotEmpty) {
        await AvatarCache.setForUserId(userId, null);
      } else if (handle.isNotEmpty) {
        await AvatarCache.setForUsername(handle, null);
      }
      return null;
    }

    // Support raw keys as well as full URLs, and cache final URL.
    String? resolved;
    if (avatar.startsWith('http://') || avatar.startsWith('https://')) {
      resolved = avatar;
    } else {
      resolved = await _resolveSigned(avatar);
    }

    if (userId != null && userId.isNotEmpty) {
      await AvatarCache.setForUserId(userId, resolved);
    }
    if (handle.isNotEmpty) {
      await AvatarCache.setForUsername(handle, resolved);
    }

    // Trigger a rebuild so that any newly-fetched displayName
    // from the profile is reflected in the header text.
    if (mounted) {
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      setState(() {});
    }

    return resolved;
  }

  String? _getCachedDisplayName() {
    String? userId = widget.authorId;
    final handle = widget.post.username
        .replaceAll('@', '')
        .trim()
        .toLowerCase();

    if (userId != null &&
        userId.isNotEmpty &&
        _displayNameByUserId.containsKey(userId)) {
      return _displayNameByUserId[userId];
    }
    if (handle.isNotEmpty && _displayNameByUsername.containsKey(handle)) {
      return _displayNameByUsername[handle];
    }
    return null;
  }

  void _openAuthorProfile() async {
    if (widget.isGuest) {
      widget.onGuestAction?.call();
      return;
    }

    // Prefer explicit authorId (userId from posts table).
    String? userId = widget.authorId;

    // Fallback: resolve by @username via profiles table.
    if ((userId == null || userId.isEmpty) && widget.post.username.isNotEmpty) {
      final handle = widget.post.username.replaceAll('@', '').trim();
      if (handle.isNotEmpty) {
        final prof = await AppwriteService.getProfileByUsername(handle);
        if (prof != null) {
          userId = prof.data['userId'] as String? ?? prof.$id;
        }
      }
    }

    // If we still don't have a userId, do nothing.
    if (userId == null || userId.isEmpty) {
      return;
    }

    // Check against the live logged-in user so we always
    // recognize our own profile correctly.
    final me = await AppwriteService.getCurrentUser();
    final isMe = me != null && userId == me.$id;

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            isMe ? const ProfileScreen() : ProfileScreen(userId: userId),
      ),
    );
  }

  Future<void> _openEditPost() async {
    if (widget.isGuest) return;
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditPostScreen(post: widget.post)),
    );
    if (updated == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Post updated')));
    }
  }

  Widget _buildTextContent() {
    final theme = Theme.of(context);
    final hasMedia =
        widget.post.imageUrl != null || widget.post.videoUrl != null;
    final bgColor = !hasMedia && widget.post.textBgColor != null
        ? Color(widget.post.textBgColor!)
        : null;
    final textAlign = bgColor != null ? TextAlign.center : TextAlign.start;
    final baseStyle = const TextStyle(
      fontSize: 21,
      fontWeight: FontWeight.w400,
      height: 1.4,
    );
    final bool bgIsLight =
        bgColor?.computeLuminance() != null &&
        (bgColor!.computeLuminance() > 0.55);
    final textStyle = baseStyle.copyWith(
      color: bgColor != null
          ? (bgIsLight ? Colors.black : Colors.white)
          : theme.colorScheme.onSurface,
      fontWeight: bgColor != null ? FontWeight.w700 : baseStyle.fontWeight,
    );

    final content = TaggableExpandableText(
      text: widget.post.content,
      style: textStyle,
      textAlign: textAlign,
      onMentionTap: _handleMentionTap,
      onHashtagTap: _handleHashtagTap,
    );

    if (bgColor == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: content,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: AspectRatio(
        aspectRatio: 1 / 0.50, // shorter rectangle than before
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [content],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaContent() {
    final urls = (widget.mediaUrls != null && widget.mediaUrls!.isNotEmpty)
        ? widget.mediaUrls!
        : (widget.post.imageUrl != null ? [widget.post.imageUrl!] : <String>[]);
    final kindLower = (widget.post.kind ?? '').toLowerCase();
    final isVideoPost =
        kindLower.contains('video') ||
        kindLower.contains('reel') ||
        kindLower.contains('short');
    final aspectRatio = _pickAspectRatio(kindLower, isVideoPost);
    const mediaMargin = EdgeInsets.symmetric(horizontal: 16);
    final borderRadius = BorderRadius.circular(16);

    // For video/reel posts with no thumbnail/image, show a video placeholder so
    // users can see it's a video and tap to open details.
    if (urls.isEmpty && isVideoPost && !widget.isDetail) {
      final theme = Theme.of(context);
      final placeholder = Container(
        margin: mediaMargin,
        child: ClipRRect(
          borderRadius: borderRadius,
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Container(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
              child: Center(
                child: Icon(
                  Icons.play_circle_fill,
                  size: widget.isDetail ? 72 : 56,
                  color: theme.colorScheme.onSurface.withOpacity(0.85),
                ),
              ),
            ),
          ),
        ),
      );
      if (widget.onOpenPost == null) return placeholder;
      return InkWell(onTap: widget.onOpenPost, child: placeholder);
    }

    if (urls.isEmpty) return const SizedBox.shrink();

    if (urls.length == 1) {
      // Base cover image
      Widget cover = _signedImage(urls.first);

      // Overlay a centered play icon for videos/reels in feed so users
      // can clearly see it's playable.
      if (isVideoPost && !widget.isDetail) {
        cover = Stack(
          fit: StackFit.expand,
          children: [
            cover,
            Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  shape: BoxShape.circle,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.play_arrow, size: 40, color: Colors.white),
                ),
              ),
            ),
          ],
        );
      }

      final image = Container(
        margin: mediaMargin,
        child: ClipRRect(
          borderRadius: borderRadius,
          child: AspectRatio(aspectRatio: aspectRatio, child: cover),
        ),
      );
      if (widget.onOpenPost == null) return image;
      return InkWell(onTap: widget.onOpenPost, child: image);
    }
    _pageController ??= PageController();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: mediaMargin,
          child: ClipRRect(
            borderRadius: borderRadius,
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: PageView.builder(
                controller: _pageController,
                itemCount: urls.length,
                onPageChanged: (index) {
                  setState(() => _currentMediaIndex = index);
                  final next = index + 1;
                  if (next < urls.length) {
                    _resolveSigned(urls[next]).then((u) {
                      if (u != null) _precache(u);
                    });
                  }
                },
                itemBuilder: (context, index) {
                  final image = _signedImage(urls[index]);
                  if (widget.onOpenPost == null) return image;
                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: widget.onOpenPost,
                    child: image,
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(urls.length, (index) {
            final isActive = index == _currentMediaIndex;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isActive ? 8 : 6,
              height: isActive ? 8 : 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? const Color(0xFF1DA1F2)
                    : Colors.grey.withOpacity(0.4),
              ),
            );
          }),
        ),
      ],
    );
  }

  double _pickAspectRatio(String kindLower, bool isVideoPost) {
    if (isVideoPost && kindLower.contains('reel')) {
      return 13 / 6; // slightly shorter portrait reels in feed
    }
    if (isVideoPost) {
      return 16 / 8; // standard landscape video look
    }
    return 10 /
        5; // photo/news default: taller than square so reactions stay visible
  }

  Widget _signedImage(String url) {
    // On web, Bunny CDN is currently not CORS-enabled / available,
    // and attempting to load those URLs causes slow failures and
    // console noise. Fall back to a lightweight placeholder instead.
    if (kIsWeb && url.contains('b-cdn.net')) {
      return Container(
        color: const Color(0xFFF3F4F6),
        child: const Center(
          child: Icon(
            LucideIcons.imageOff,
            size: 40,
            color: Color(0xFF9CA3AF),
          ),
        ),
      );
    }

    return FutureBuilder<String?>(
      future: _resolveSigned(url),
      builder: (context, snap) {
        final imgUrl = snap.data;
        if (imgUrl == null) {
          return const SizedBox.expand(
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return CachedNetworkImage(
          imageUrl: imgUrl,
          width: double.infinity,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholderFadeInDuration: Duration.zero,
          placeholder: (c, s) => Container(color: const Color(0xFFF3F4F6)),
          errorWidget: (c, s, e) => Container(
            color: const Color(0xFFF3F4F6),
            child: const Center(
              child: Icon(
                LucideIcons.imageOff,
                size: 40,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<String?> _resolveSigned(String url) async {
    if (_signedCache.containsKey(url)) return _signedCache[url]!;

    // If this is an Appwrite Storage URL, return it as-is (no Wasabi signing).
    if (url.contains('cloud.appwrite.io')) {
      _signedCache[url] = url;
      return url;
    }

    // Legacy Wasabi media: support both raw keys and full signed URLs.
    String key = url;
    if (url.contains('://')) {
      try {
        final uri = Uri.parse(url);
        // S3/Wasabi path-style URL: /bucket/key...
        if (uri.host.contains('wasabisys.com') &&
            uri.pathSegments.length >= 2) {
          key = uri.pathSegments.skip(1).join('/');
        }
      } catch (_) {
        key = url;
      }
    }

    final signed = await WasabiService.getSignedUrl(key);
    _signedCache[url] = signed;
    return signed;
  }

  Widget _buildVideoMeta() {
    final theme = Theme.of(context);
    final title = widget.post.title?.trim();
    final description = widget.post.content.trim();
    if ((title == null || title.isEmpty) && description.isEmpty) {
      return const SizedBox.shrink();
    }
    const baseStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.w500);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null && title.isNotEmpty)
            Text(
              title,
              style: baseStyle.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 4),
            if (widget.videoDescriptionMaxLines != null &&
                widget.onVideoDescriptionTap != null)
              _buildVideoDescriptionPreview(
                description,
                theme,
                widget.videoDescriptionMaxLines!,
                widget.onVideoDescriptionTap!,
              )
            else
              _ExpandableText(
                text: description,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                ).copyWith(color: theme.colorScheme.onSurface),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoDescriptionPreview(
    String description,
    ThemeData theme,
    int maxLines,
    VoidCallback onTap,
  ) {
    final baseStyle = TextStyle(
      fontSize: 15,
      height: 1.4,
      color: theme.colorScheme.onSurface,
    );
    const maxChars = 120;
    var snippet = description.trim();
    var truncated = false;
    if (snippet.length > maxChars) {
      snippet = snippet.substring(0, maxChars);
      truncated = true;
    }
    return GestureDetector(
      onTap: onTap,
      child: RichText(
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: baseStyle,
          children: [
            TextSpan(text: snippet),
            if (truncated) const TextSpan(text: '... '),
            TextSpan(
              text: ' See more',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _precache(String url) {
    if (mounted) {
      precacheImage(CachedNetworkImageProvider(url), context);
    }
  }

  Widget _buildActions() {
    final theme = Theme.of(context);
    final iconDefault =
        theme.iconTheme.color ?? theme.colorScheme.onSurfaceVariant;
    final countColor = theme.colorScheme.onSurfaceVariant;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildLikeAction(),
          _buildActionButton(
            LucideIcons.messageCircle,
            _commentCount,
            iconDefault,
            _openComments,
            countColor,
          ),
          _buildActionButton(
            LucideIcons.repeat2,
            _repostCount,
            _hasReposted ? const Color(0xFF1DA1F2) : iconDefault,
            _repostPost,
            countColor,
          ),
          _buildShareAction(),
          _buildActionButton(
            LucideIcons.barChart2,
            _impressionCount,
            iconDefault,
            () {},
            countColor,
            widget.showViewsLabel ? 'Views' : null,
          ),
          IconButton(
            icon: Icon(
              _isSaved ? LucideIcons.bookmark : LucideIcons.bookmark,
              color: _isSaved ? theme.colorScheme.primary : iconDefault,
            ),
            onPressed: _toggleSave,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    int? count,
    Color? color,
    VoidCallback onPressed, [
    Color? countColor,
    String? label,
  ]) {
    return Row(
      children: [
        IconButton(
          icon: Icon(icon, color: color),
          onPressed: onPressed,
        ),
        if (count != null)
          Row(
            children: [
              _AnimatedCount(value: count, color: countColor),
              if (label != null) ...[
                const SizedBox(width: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: countColor ?? Colors.grey,
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildShareAction() {
    final theme = Theme.of(context);
    final iconDefault =
        theme.iconTheme.color ?? theme.colorScheme.onSurfaceVariant;
    final countColor = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        IconButton(
          icon: Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(math.pi),
            child: Icon(Icons.reply, color: iconDefault),
          ),
          onPressed: () {
            setState(() {
              _shareCount++;
            });
            AppwriteService.incrementPostShares(widget.post.id, 1);
            _sharePost();
          },
        ),
        _AnimatedCount(value: _shareCount, color: countColor),
      ],
    );
  }

  Widget _buildLikeAction() {
    final theme = Theme.of(context);
    final activeColor = const Color(0xFFFF2D55); // vibrant pink/red
    final inactiveColor =
        theme.iconTheme.color ?? theme.colorScheme.onSurfaceVariant;

    return Row(
      children: [
        InkResponse(
          onTap: _toggleLike,
          borderRadius: BorderRadius.circular(999),
          radius: 24,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _isLiked
                  ? activeColor.withOpacity(0.12)
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isLiked ? Icons.favorite : Icons.favorite_border,
              color: _isLiked ? activeColor : inactiveColor,
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: 4),
        _AnimatedCount(
          value: _likeCount,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }

  Future<void> _toggleFollow() async {
    if (widget.isGuest || widget.authorId == null || _currentUserId == null) {
      return;
    }
    final targetFollow = !_isFollowing;
    setState(() => _isFollowing = targetFollow);
    try {
      if (targetFollow) {
        await AppwriteService.followUser(widget.authorId!);
      } else {
        await AppwriteService.unfollowUser(widget.authorId!);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isFollowing = !targetFollow);
      }
    }
  }

  Future<void> _toggleLike() async {
    if (widget.isGuest) {
      widget.onGuestAction?.call();
      return;
    }
    final targetLike = !_isLiked;
    final previousCount = _likeCount;
    setState(() {
      _isLiked = targetLike;
      _likeCount += targetLike ? 1 : -1;
      if (_likeCount < 0) _likeCount = 0;
      _likeManuallySet = true;
      _likeCache[widget.post.id] = _isLiked;
    });
    try {
      if (targetLike) {
        await AppwriteService.likePost(widget.post.id);
      } else {
        await AppwriteService.unlikePost(widget.post.id);
      }
    } catch (_) {
      // Revert UI if the backend update fails.
      if (!mounted) return;
      setState(() {
        _isLiked = !targetLike;
        _likeCount = previousCount;
        _likeCache[widget.post.id] = _isLiked;
      });
    }
  }

  Future<void> _repostPost() async {
    if (widget.isGuest) {
      widget.onGuestAction?.call();
      return;
    }
    final targetRepost = !_hasReposted;
    final previousCount = _repostCount;
    setState(() {
      _hasReposted = targetRepost;
      _repostCount += targetRepost ? 1 : -1;
      if (_repostCount < 0) _repostCount = 0;
    });
    try {
      await AppwriteService.repostPost(widget.post.id);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(targetRepost ? 'Post reposted' : 'Repost removed'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasReposted = !_hasReposted;
        _repostCount = previousCount;
      });
    }
  }

  Future<void> _toggleSave() async {
    if (widget.isGuest) {
      widget.onGuestAction?.call();
      return;
    }
    final targetSave = !_isSaved;
    setState(() => _isSaved = targetSave);
    try {
      if (targetSave) {
        await AppwriteService.savePost(widget.post.id);
      } else {
        await AppwriteService.unsavePost(widget.post.id);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaved = !targetSave);
      }
    }
  }

  void _openComments() {
    if (widget.isGuest) {
      widget.onGuestAction?.call();
      return;
    }
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CommentScreen(post: widget.post),
        ),
      );
    }
  }

  void _sharePost() {
    ShareUtils.sharePost(
      postId: widget.post.id,
      username: widget.post.username,
      content: widget.post.content,
    );
  }

  Future<void> _handleMentionTap(String username) async {
    final handle = username.replaceAll('@', '').trim();
    if (handle.isEmpty) return;
    final prof = await AppwriteService.getProfileByUsername(handle);
    if (!mounted) return;
    if (prof == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('User @$handle not found')));
      return;
    }
    final data = prof.data;
    final userId = data['userId'] as String? ?? prof.$id;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => ProfileScreen(userId: userId)),
    );
  }

  void _handleHashtagTap(String tag) {
    final clean = tag.replaceAll('#', '').trim();
    if (clean.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => HashtagFeedScreen(tag: clean)),
    );
  }

  void _showReportMenu() {
    showModalBottomSheet(
      context: context,
      builder: (bcontext) {
        return Wrap(
          children: [
            if (_currentUserId != null &&
                widget.authorId != null &&
                widget.authorId == _currentUserId)
              ListTile(
                leading: const Icon(LucideIcons.edit3),
                title: const Text('Edit Post'),
                onTap: () async {
                  Navigator.of(bcontext).pop();
                  await _openEditPost();
                },
              ),
            if (_currentUserId != null &&
                widget.authorId != null &&
                widget.authorId == _currentUserId)
              ListTile(
                leading: const Icon(LucideIcons.zap),
                title: const Text('Promote with ads'),
                onTap: () async {
                  Navigator.of(bcontext).pop();
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BoostPostScreen(post: widget.post),
                    ),
                  );
                },
              ),
            if (_currentUserId != null &&
                widget.post.sourcePostId == null &&
                widget.authorId == _currentUserId)
              ListTile(
                leading: const Icon(LucideIcons.trash2, color: Colors.red),
                title: const Text(
                  'Delete Post',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  Navigator.of(bcontext).pop();
                  final messenger = ScaffoldMessenger.of(context);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Post'),
                      content: const Text(
                        'Are you sure you want to delete this post?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                  try {
                    await AppwriteService.deletePost(widget.post.id);
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Post deleted')),
                    );
                    // Inform parent lists so they can remove this card instantly.
                    widget.onDeleted?.call();
                  } catch (e) {
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Failed to delete post')),
                    );
                  }
                },
              ),
            ListTile(
              leading: const Icon(LucideIcons.flag, color: Colors.red),
              title: const Text(
                'Report Post',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.of(bcontext).pop();
                _showReportConfirmation();
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.x, color: Colors.grey),
              title: const Text('Cancel'),
              onTap: () => Navigator.of(bcontext).pop(),
            ),
          ],
        );
      },
    );
  }

  void _showReportConfirmation() {
    showDialog(
      context: context,
      builder: (dcontext) => AlertDialog(
        title: const Text('Report Post'),
        content: const Text('Are you sure you want to report this post?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dcontext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(dcontext);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              try {
                await AppwriteService.reportPost(
                  widget.post.id,
                  'Inappropriate content',
                );
                if (!mounted) return;
                navigator.pop();
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('Post reported.')),
                );
              } catch (e) {
                if (!mounted) return;
                navigator.pop();
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('Failed to report post.')),
                );
              }
            },
            child: const Text('Report', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _AnimatedCount extends StatelessWidget {
  final int value;
  final Color? color;

  const _AnimatedCount({required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      value.toString(),
      style: TextStyle(color: color ?? Colors.grey[700], fontSize: 14),
    );
  }
}

class _ExpandableText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _ExpandableText({required this.text, required this.style});

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final span = TextSpan(text: widget.text, style: widget.style);
        final tp = TextPainter(
          text: span,
          maxLines: 3,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflow = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: widget.style,
              maxLines: _expanded ? null : 3,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
            ),
            if (overflow)
              GestureDetector(
                onTap: () {
                  setState(() => _expanded = !_expanded);
                },
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _expanded ? 'See less' : 'See more',
                    style: TextStyle(
                      color: const Color(0xFF1DA1F2),
                      fontSize: (widget.style.fontSize ?? 16) * 0.85,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

String _formatTimestamp(DateTime timestamp) {
  // Always measure from local time and clamp negative differences to zero,
  // so the counter never counts backwards when clocks/timezones differ.
  final now = DateTime.now();
  Duration diff = now.difference(timestamp.toLocal());

  if (diff.isNegative) {
    diff = Duration.zero;
  }

  if (diff.inSeconds < 60) {
    final s = diff.inSeconds;
    return '${s}s';
  }
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return '${m}m';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return '${h}h';
  }
  if (diff.inDays < 30) {
    final d = diff.inDays;
    return '${d}d';
  }

  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final day = timestamp.day;
  final month = months[timestamp.month - 1];

  if (timestamp.year == now.year) {
    // Same year, older than ~1 month: "5 Nov"
    return '$day $month';
  } else {
    // Different year: "5 Nov 2025"
    final year = timestamp.year;
    return '$day $month $year';
  }
}
