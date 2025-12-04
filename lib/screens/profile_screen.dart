import 'dart:async';

import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as aw;
import '../services/appwrite_service.dart';
import '../services/storage_service.dart';
import '../services/profile_cache.dart';
import '../models/post.dart';
import '../widgets/post_card.dart';
import '../widgets/reel_player.dart';
import '../widgets/pending_upload_banner.dart';
import 'video_detail_screen.dart';
import 'post_detail_screen.dart';
import 'edit_profile_screen.dart';
import '../models/chat.dart';
import 'individual_chat_screen.dart';
import 'dashboard_screen.dart';
import 'monetization_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId;
  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _currentUserId;
  bool get _isCurrentUser =>
      widget.userId == null || (widget.userId != null && widget.userId == _currentUserId);
  bool _isFollowing = false;
  bool _followLoaded = false;
  String? _targetUserId;
  int _postsCount = 0;
  int _followersCount = 0;
  int _followingCount = 0;
  DateTime? _joinedAt;
  final List<Post> _posts = [];
  final Map<String, List<String>> _mediaByPostId = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    try {
      final me = await AppwriteService.getCurrentUser();
      final id = widget.userId ?? me?.$id;
      if (id == null) return;
      _targetUserId = id;
      _currentUserId = me?.$id;

      if (!force) {
        final cached = ProfileCache.get(id);
        if (cached != null) {
          setState(() {
            _profile = cached.profile;
      _posts
        ..clear()
        ..addAll(cached.posts);
      _mediaByPostId
        ..clear()
        ..addAll(cached.mediaByPostId);
      _postsCount = cached.postsCount;
      _followersCount = cached.followersCount;
      _followingCount = cached.followingCount;
      _joinedAt = cached.joinedAt;
      _loading = false;
      _followLoaded = false;
          });
          // Even when cached, refresh follow state so the button reflects
          // whether the current user already follows this profile.
          unawaited(_syncFollowState());
          return;
        }
      }
      final prof = await AppwriteService.getProfileByUserId(id);
      final userMeta = await AppwriteService.getUserMetaByUserId(id);
      _targetUserId = prof?.data['userId'] as String? ?? id;
      await _syncFollowState();
      // Load counts
      final followingIds = await AppwriteService.getFollowingUserIds(id);
      final followersCount = await AppwriteService.getFollowerCount(id);
      // Load posts for this user
      final aw.RowList postsList = await AppwriteService.fetchPostsByUserIds([id], limit: 50);
      final rows = postsList.rows;

      // Load repost events for this user (mirror behavior in profile feed)
      final aw.RowList repostsList =
          await AppwriteService.fetchRepostsByUserIds([id], limit: 50);
      final repostRows = repostsList.rows;
      _mediaByPostId.clear();
      _posts.clear();
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
        _posts.add(
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

      // Mirror reposts in profile feed as "X reposted" entries
      for (final r in repostRows) {
        final rData = r.data;
        final postId = rData['postId'] as String?;
        if (postId == null) continue;
        try {
          final original =
              await AppwriteService.getRow(AppwriteService.postsCollectionId, postId);
          final data = original.data;
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

          _mediaByPostId[postId] = mediaForUi;

          _posts.add(
            Post(
              id: postId,
              username: data['username'] as String? ?? 'No Name',
              userAvatar: data['userAvatar'] as String? ?? '',
              content: data['content'] as String? ?? '',
              textBgColor: data['textBgColor'] as int?,
              timestamp: rData['createdAt'] != null
                  ? DateTime.tryParse(rData['createdAt'] as String? ?? '') ?? DateTime.now()
                  : DateTime.now(),
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
              sourcePostId: postId,
              sourceUserId: _targetUserId,
              sourceUsername: _profile?['displayName'] ?? _profile?['username'] ?? '',
            ),
          );
        } catch (_) {
          continue;
        }
      }
      if (!mounted) return;
      final Map<String, dynamic> profileData = {};
      if (prof != null) {
        profileData.addAll(prof.data);
      }
      if (userMeta != null) {
        final u = userMeta.data;
        profileData['username'] ??= u['username'];
        profileData['email'] ??= u['email'];
      }
      if (profileData.isEmpty && me != null) {
        profileData['displayName'] = me.name;
        profileData['username'] = me.name;
      }

      // Resolve Bunny/Wasabi keys for avatar/cover to signed URLs for display.
      final rawAvatar = profileData['avatarUrl'] as String?;
      if (rawAvatar != null &&
          rawAvatar.isNotEmpty &&
          !rawAvatar.startsWith('http')) {
        try {
          final signed = await WasabiService.getSignedUrl(rawAvatar);
          profileData['avatarUrl'] = signed;
        } catch (_) {}
      }
      final rawCover = profileData['coverUrl'] as String?;
      if (rawCover != null &&
          rawCover.isNotEmpty &&
          !rawCover.startsWith('http')) {
        try {
          final signed = await WasabiService.getSignedUrl(rawCover);
          profileData['coverUrl'] = signed;
        } catch (_) {}
      }

      final joinedAt = prof != null
          ? DateTime.tryParse(prof.$createdAt) ?? DateTime.now()
          : null;

      final entry = ProfileCacheEntry(
        profile: profileData.isNotEmpty ? profileData : null,
        posts: List<Post>.from(_posts),
        mediaByPostId: Map<String, List<String>>.from(_mediaByPostId),
        postsCount: postsList.total,
        followersCount: followersCount,
        followingCount: followingIds.length,
        joinedAt: joinedAt,
      );
      ProfileCache.set(id, entry);

      setState(() {
        _profile = entry.profile;
        _postsCount = entry.postsCount;
        _followingCount = entry.followingCount;
        _followersCount = entry.followersCount;
        _joinedAt = entry.joinedAt;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _syncFollowState() async {
    final me = _currentUserId;
    final target = _targetUserId;
    if (me == null || target == null || me == target) {
      setState(() {
        _isFollowing = false;
        _followLoaded = true;
      });
      return;
    }
    try {
      final following = await AppwriteService.isFollowing(me, target);
      if (!mounted) return;
      setState(() {
        _isFollowing = following;
        _followLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isFollowing = false;
        _followLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final displayName = _profile?['displayName'] ?? _profile?['username'] ?? 'User Profile';
    final username = _profile?['username'] ?? 'user';
    final avatar = _profile?['avatarUrl'] as String?;
    final bio = _profile?['bio'] as String?;
    final category = _profile?['category'] as String?;
    final coverUrl = _profile?['coverUrl'] as String?;

    final postsOnly = _posts.where((p) => !_isVideoPost(p) && !_isNewsPost(p)).toList();
    final videosOnly = _posts.where(_isVideoPost).toList();
    final newsOnly = _posts.where(_isNewsPost).toList();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.colorScheme.surface,
          elevation: 1,
          leading: _isCurrentUser
              ? null
              : IconButton(
                  icon: Icon(Icons.arrow_back, color: theme.iconTheme.color),
                  onPressed: () => Navigator.of(context).pop(),
                ),
          title: Text(
            displayName,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          centerTitle: true,
        ),
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProfileHeader(
                      theme: theme,
                      displayName: displayName,
                      username: username,
                      avatar: avatar,
                      bio: bio,
                      category: category,
                      coverUrl: coverUrl,
                    ),
                    _buildActionButtons(theme),
                    const SizedBox(height: 12),
                    _buildDashboardAndMonetization(theme),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _ProfileTabBarDelegate(
                  theme: theme,
                  tabBar: TabBar(
                    labelColor: theme.colorScheme.onSurface,
                    unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                    indicatorColor: theme.colorScheme.primary,
                    tabs: const [
                      Tab(text: 'Posts'),
                      Tab(text: 'Videos'),
                      Tab(text: 'News'),
                      Tab(text: 'All'),
                    ],
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(
            children: [
              _buildPostsList(postsOnly),
              _buildPostsList(videosOnly),
              _buildPostsList(newsOnly),
              _buildPostsList(_posts),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleFollow() async {
    final me = await AppwriteService.getCurrentUser();
    if (me == null || _targetUserId == null) return;
    try {
      if (_isFollowing) {
        await AppwriteService.unfollowUser(_targetUserId!);
        if (!mounted) return;
        setState(() {
          _isFollowing = false;
          _followersCount = (_followersCount - 1).clamp(0, 1 << 31);
        });
      } else {
        await AppwriteService.followUser(_targetUserId!);
        if (!mounted) return;
        setState(() {
          _isFollowing = true;
          _followersCount = _followersCount + 1;
        });
      }
      // Inform user
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isFollowing ? 'Followed' : 'Unfollowed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action failed: $e')),
      );
    }
  }

  Future<void> _openChatWithUser() async {
    final targetId = _targetUserId ?? _profile?['userId'] as String? ?? widget.userId;
    if (targetId == null || targetId.isEmpty) return;
    final me = await AppwriteService.getCurrentUser();
    if (me == null) return;
    try {
      final chatId = await AppwriteService.getChatId(me.$id, targetId);
      final targetProfile = await AppwriteService.getProfileByUserId(targetId);
      final data = targetProfile?.data ?? <String, dynamic>{};
      final displayName = (data['displayName'] as String?)?.trim() ??
          (data['username'] as String?)?.trim() ??
          'User';
      final avatar = (data['avatarUrl'] as String?) ?? '';
      final chat = Chat(
        id: chatId,
        partnerId: targetId,
        partnerName: displayName,
        partnerAvatar: avatar,
        lastMessage: '',
        timestamp: DateTime.now(),
        unreadCount: 0,
        isOnline: false,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => IndividualChatScreen(chat: chat)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open chat: $e')),
      );
    }
  }

  void _shareProfile() {
    // Placeholder: you can wire this to share profile URL later.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Share profile coming soon')),
    );
  }

  Widget _buildStat(String label, int value, ThemeData theme) {
    final base = theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: base,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: base,
          ),
        ),
      ],
    );
  }

  Widget _buildPostsList(List<Post> posts) {
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: posts.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) return const PendingUploadBanner();
          final post = posts[index - 1];
          final isVideo = _isVideoPost(post);
          final isReel = _isReelPost(post);
          return PostCard(
            post: post,
            isGuest: false,
            onGuestAction: null,
            mediaUrls: _mediaByPostId[post.id],
            authorId: _targetUserId,
            // Do not count impressions/views just from profile cards;
            // real views come from actual video playback screens.
            trackImpressions: !isVideo,
            showReelBadge: isReel,
            onDeleted: () {
              setState(() {
                _posts.removeWhere((p) => p.id == post.id);
              });
            },
            onOpenPost: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) {
                    if (isReel && isVideo && post.videoUrl != null && post.videoUrl!.isNotEmpty) {
                      return ReelPlayer(
                        post: post,
                        isGuest: false,
                        onGuestAction: null,
                        authorId: _targetUserId,
                      );
                    }
                    if (isVideo && post.videoUrl != null && post.videoUrl!.isNotEmpty) {
                      return VideoDetailScreen(
                        post: post,
                        mediaUrls: _mediaByPostId[post.id],
                        authorId: _targetUserId,
                        isGuest: false,
                        onGuestAction: null,
                      );
                    }
                    return PostDetailScreen(
                      post: post,
                      mediaUrls: _mediaByPostId[post.id],
                      authorId: _targetUserId,
                      isGuest: false,
                      onGuestAction: null,
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildProfileHeader({
    required ThemeData theme,
    required String displayName,
    required String username,
    required String? avatar,
    required String? bio,
    required String? category,
    required String? coverUrl,
  }) {
    final coverHeight = 190.0;
    final joinedLabel = _joinedAt != null ? _formatJoined(_joinedAt!) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: coverHeight,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (coverUrl != null && coverUrl.isNotEmpty)
                Image.network(
                  coverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: theme.colorScheme.primary,
                  ),
                )
              else
                Container(color: theme.colorScheme.primary),
              Positioned.fill(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: CircleAvatar(
                      radius: 46,
                      backgroundColor: theme.scaffoldBackgroundColor,
                      child: CircleAvatar(
                        radius: 42,
                        backgroundImage:
                            (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null,
                        backgroundColor: Colors.grey[300],
                        child: (avatar == null || avatar.isEmpty)
                            ? Icon(Icons.person, color: Colors.grey[600], size: 36)
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '@$username',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildStat('Posts', _postsCount, theme),
                  const SizedBox(width: 18),
                  _buildStat('Followers', _followersCount, theme),
                  const SizedBox(width: 18),
                  _buildStat('Following', _followingCount, theme),
                ],
              ),
              if (category != null && category.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  category,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
              if (bio != null && bio.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  bio,
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
              if (joinedLabel != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.calendar_today,
                        size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      'Joined $joinedLabel',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildActionButtons(ThemeData theme) {
    Widget? leadingButton;
    if (_isCurrentUser) {
      leadingButton = OutlinedButton(
        onPressed: () {
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (_) => const EditProfileScreen(),
                ),
              )
              .then((_) => _load());
        },
        style: OutlinedButton.styleFrom(
          backgroundColor: theme.colorScheme.surface,
          foregroundColor: theme.colorScheme.onSurface,
          side: BorderSide(color: theme.dividerColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: const Text('Edit profile'),
      );
    } else if (_followLoaded) {
      leadingButton = OutlinedButton(
        onPressed: _toggleFollow,
        style: OutlinedButton.styleFrom(
          backgroundColor: _isFollowing ? theme.colorScheme.surface : const Color(0xFF1DA1F2),
          foregroundColor: _isFollowing ? theme.colorScheme.onSurface : Colors.white,
          side: _isFollowing ? BorderSide(color: theme.dividerColor) : BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: Text(_isFollowing ? 'Following' : 'Follow'),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          if (leadingButton != null) Expanded(child: leadingButton),
          if (leadingButton != null) const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: _isCurrentUser ? _shareProfile : _openChatWithUser,
              style: OutlinedButton.styleFrom(
                backgroundColor: theme.colorScheme.surface,
                foregroundColor: theme.colorScheme.onSurface,
                side: BorderSide(color: theme.dividerColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: Text(_isCurrentUser ? 'Share profile' : 'Message'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardAndMonetization(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = theme.colorScheme.surface;
    final borderColor =
        isDark ? Colors.white12 : theme.dividerColor.withOpacity(0.7);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Creator tools',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildMiniToolCard(
                    theme: theme,
                    icon: Icons.insights_outlined,
                    title: 'Dashboard',
                    subtitle: 'Insights & performance',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DashboardScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildMiniToolCard(
                    theme: theme,
                    icon: Icons.monetization_on_outlined,
                    title: 'Monetization',
                    subtitle: 'Earnings & eligibility',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MonetizationScreen()),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniToolCard({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDark
              ? Colors.white.withOpacity(0.03)
              : theme.colorScheme.surfaceVariant.withOpacity(0.4),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withOpacity(0.12),
              ),
              child: Icon(
                icon,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isVideoPost(Post post) {
    final kindLower = post.kind?.toLowerCase() ?? '';
    if (kindLower.contains('video') ||
        kindLower.contains('reel') ||
        kindLower.contains('short')) {
      return true;
    }
    if (post.videoUrl != null && post.videoUrl!.isNotEmpty) {
      return true;
    }
    final media = _mediaByPostId[post.id] ?? const <String>[];
    return media.any(_isVideoUrl);
  }

  bool _isReelPost(Post post) {
    final kind = post.kind?.toLowerCase();
    if (kind == null) return false;
    return kind.contains('reel') || kind.contains('short');
  }

  bool _isNewsPost(Post post) {
    final kind = post.kind?.toLowerCase();
    if (kind == null) return false;
    return kind.contains('news') || kind.contains('blog');
  }

  bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm');
  }

  String _formatJoined(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final m = months[date.month - 1];
    return '$m ${date.year}';
  }
}

class _ProfileTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final ThemeData theme;

  _ProfileTabBarDelegate({
    required this.tabBar,
    required this.theme,
  });

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: theme.colorScheme.surface,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _ProfileTabBarDelegate oldDelegate) {
    return false;
  }
}
