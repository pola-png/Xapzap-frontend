import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as aw;
import 'package:appwrite/appwrite.dart' show RealtimeSubscription;
import '../models/post.dart';
import '../services/appwrite_service.dart';
import '../services/storage_service.dart';
import '../services/feed_cache.dart';
import '../widgets/post_card.dart';
import '../widgets/reel_player.dart';
import '../widgets/watch_video_card.dart';
import '../widgets/guest_prompt.dart';
import '../models/status.dart';
import '../models/story.dart';
import '../services/story_manager.dart';
import '../widgets/story_avatar.dart';
import '../widgets/keep_alive_tab.dart';
import '../services/avatar_cache.dart';
import '../services/ad_helper.dart';
import 'story_publish_screen.dart';
import 'chat_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'search_screen.dart';
import 'post_detail_screen.dart';
import 'video_detail_screen.dart';
import 'status_viewer_screen.dart';
import '../widgets/pending_upload_banner.dart';
import 'live_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final List<Post> _forYouPosts = FeedCache.forYouPosts;
  final List<Post> _followingPosts = FeedCache.followingPosts;
  final Map<String, List<String>> _mediaByPostId = FeedCache.mediaByPostId;
  final Map<String, String> _authorByPostId = FeedCache.authorByPostId;
  final List<Story> _stories = [];
  final List<StatusUpdate> _statusUpdates = [];
  final ScrollController _forYouController = ScrollController();
  final ScrollController _followingController = ScrollController();
  final ScrollController _watchController = ScrollController();
  final ScrollController _newsController = ScrollController();
  RealtimeSubscription? _postsSub;
  bool _monetizedAccepted = false;
  late TabController _tabController;
  bool _isLoading = false;
  bool _isGuest = true;
  String? _currentUserId;
  String? _forYouCursor = FeedCache.forYouCursor;
  String? _followingCursor = FeedCache.followingCursor;
  List<String> _followingIds = [];
  late final VoidCallback _storiesListener;
  final ImagePicker _storyPicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _checkUser();
    _tabController = TabController(length: 6, vsync: this);
    StoryManager.init();
    _storiesListener = _syncStories;
    StoryManager.stories.addListener(_storiesListener);
    _syncStories();
    StoryManager.loadFromServer();
    _forYouController.addListener(() => _onScroll(_forYouController, true));
    _followingController.addListener(
      () => _onScroll(_followingController, false),
    );
    _watchController.addListener(() => _onScroll(_watchController, true));
    _newsController.addListener(() => _onScroll(_newsController, true));

    // Only fetch from network if we don't already have cached feeds.
    if (!FeedCache.hasForYou) {
      _refreshFeed(true);
    }
    if (!FeedCache.hasFollowing) {
      _refreshFeed(false);
    }
    _subscribePostsRealtime();
  }

  Future<void> _checkUser() async {
    final user = await AppwriteService.getCurrentUser();
    setState(() {
      _isGuest = user == null;
      _currentUserId = user?.$id;
    });
    if (user != null) {
      _followingIds = await AppwriteService.getFollowingUserIds(user.$id);
      // listen for follow/unfollow changes
      AppwriteService.followingVersion.addListener(() async {
        final me = await AppwriteService.getCurrentUser();
        if (me != null && mounted) {
          _followingIds = await AppwriteService.getFollowingUserIds(me.$id);
          await _refreshFeed(false);
        }
      });
      if (_followingIds.isNotEmpty && _followingPosts.isEmpty) {
        await _refreshFeed(false);
      }

      // Update current user's story avatar, preferring persistent cache
      // so it does not refresh on navigation.
      try {
        String? avatar = AvatarCache.getForUserId(user.$id);
        if (avatar == null) {
          final prof = await AppwriteService.getProfileByUserId(user.$id);
          final raw = prof?.data['avatarUrl'] as String?;
          if (raw != null && raw.isNotEmpty) {
            if (raw.startsWith('http://') || raw.startsWith('https://')) {
              avatar = raw;
            } else {
              try {
                avatar = await WasabiService.getSignedUrl(raw);
              } catch (_) {
                avatar = raw;
              }
            }
            await AvatarCache.setForUserId(user.$id, avatar);
          }
        }
        final accountName = user.name.trim();
        String displayName = 'You';
        final prof = await AppwriteService.getProfileByUserId(user.$id);
        if (prof != null) {
          final data = prof.data;
          final rawName = (data['displayName'] as String?)?.trim();
          final rawUsername = (data['username'] as String?)?.trim();
          displayName = rawName?.isNotEmpty == true
              ? rawName!
              : rawUsername?.isNotEmpty == true
              ? rawUsername!
              : (accountName.isNotEmpty ? accountName : 'You');
        } else if (accountName.isNotEmpty) {
          displayName = accountName;
        }
        StoryManager.updateMyProfile(
          userAvatar: avatar ?? '',
          username: displayName,
        );
      } catch (_) {}
    }
  }

  void _syncStories() {
    final values = StoryManager.stories.value;
    _statusUpdates
      ..clear()
      ..addAll(values);
    final visible = values.where(
      (status) => status.id == 'me' || !status.isViewed,
    );
    _stories
      ..clear()
      ..addAll(
        visible.map(
          (status) => Story(
            id: status.id,
            username: status.username,
            imageUrl: status.mediaUrls.isNotEmpty
                ? status.mediaUrls.first
                : status.userAvatar,
            isViewed: status.isViewed,
          ),
        ),
      );
  }

  void _subscribePostsRealtime() {
    final channel =
        'databases.${AppwriteService.databaseId}.collections.${AppwriteService.postsCollectionId}.documents';
    try {
      _postsSub = AppwriteService.realtime.subscribe([channel]);
      _postsSub?.stream.listen((event) async {
        if (!mounted) return;
        if (event.events.isEmpty) return;
        final name = event.events.first;
        // Only refresh feeds when posts are created or deleted.
        if (name.contains('.create') || name.contains('.delete')) {
          await _refreshFeed(true);
          await _refreshFeed(false);
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final onSurface = theme.colorScheme.onSurface;
        final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;

        // Treat as desktop layout only on wide screens; narrow web should use
        // the same mobile layout as the native app.
        if (constraints.maxWidth > 1100) {
          return _buildDesktopScaffold(theme, onSurface, onSurfaceVariant);
        }
        return _buildMobileScaffold(theme, onSurface, onSurfaceVariant);
      },
    );
  }

  Widget _buildMobileScaffold(
    ThemeData theme,
    Color onSurface,
    Color onSurfaceVariant,
  ) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          final index = _tabController.index;
          // For For You, Watch, Reels, News: refresh For You feed.
          if (index == 0 || index == 1 || index == 2 || index == 4) {
            await _refreshFeed(true);
          } else if (index == 5) {
            // Following tab
            await _refreshFeed(false);
          }
        },
        child: NestedScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              automaticallyImplyLeading: false,
              backgroundColor: theme.colorScheme.background,
              floating: true,
              pinned: true,
              title: const Text(
                'XapZap',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1DA1F2),
                ),
              ),
              actions: [
                IconButton(
                  icon: Icon(Icons.search, color: onSurface, size: 28),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const SearchScreen(),
                      ),
                    );
                  },
                ),
              ],
              bottom: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: onSurface,
                unselectedLabelColor: onSurfaceVariant,
                indicatorColor: onSurface,
                onTap: _handleTabTap,
                tabs: const [
                  Tab(text: 'For You'),
                  Tab(text: 'Watch'),
                  Tab(text: 'Reels'),
                  Tab(text: 'Live'),
                  Tab(text: 'News'),
                  Tab(text: 'Following'),
                ],
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: _buildTabViews(),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopScaffold(
    ThemeData theme,
    Color onSurface,
    Color onSurfaceVariant,
  ) {
    final bool isWatchTab = _tabController.index == 1;
    return Scaffold(
      // Header is rendered by MainScreen on desktop.
      body: Row(
        children: [
          SizedBox(
            width: 220,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
              children: [
                const SizedBox(height: 4),
                _buildSideNavItem(Icons.home_filled, 'For You', 0),
                _buildSideNavItem(Icons.ondemand_video_outlined, 'Watch', 1),
                _buildSideNavItem(Icons.video_library_outlined, 'Reels', 2),
                _buildSideNavItem(Icons.wifi_tethering, 'Live', 3),
                _buildSideNavItem(Icons.article_outlined, 'News', 4),
                _buildSideNavItem(Icons.groups_outlined, 'Following', 5),
              ],
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  // On Watch tab, keep feed narrower for large screens.
                  maxWidth: isWatchTab ? 1200 : double.infinity,
                ),
                child: TabBarView(
                  controller: _tabController,
                  children: _buildTabViews(),
                ),
              ),
            ),
          ),
          if (!isWatchTab)
            SizedBox(width: 220, child: _buildRightSidebar(theme)),
        ],
      ),
    );
  }

  Widget _buildSideNavItem(
    IconData icon,
    String label,
    int tabIndex, {
    VoidCallback? onTap,
  }) {
    final isSelected = tabIndex >= 0 && _tabController.index == tabIndex;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      leading: Icon(icon, color: isSelected ? const Color(0xFF1DA1F2) : null),
      title: Text(label),
      selected: isSelected,
      onTap: () {
        if (onTap != null) {
          onTap();
          return;
        }
        if (tabIndex >= 0) {
          _handleTabTap(tabIndex);
          setState(() => _tabController.index = tabIndex);
        }
      },
    );
  }

  Widget _buildRightSidebar(ThemeData theme) {
    final textColor = theme.colorScheme.onSurface;
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trending',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            ...['#xapzap', '#news', '#reels', '#tech', '#music'].map(
              (t) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  t,
                  style: TextStyle(fontSize: 14, color: textColor),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Notifications',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'You\'re all caught up.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Chats',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.chat_bubble_outline, size: 20),
              title: const Text('Open chats'),
              onTap: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const ChatScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTabViews() {
    return [
      KeepAliveTab(
        builder: (_) => _buildFeed(_forYouPosts, _forYouController, true),
      ),
      _buildWatchTab(),
      _buildReelsTab(),
      KeepAliveTab(builder: (_) => _buildLiveTab()),
      KeepAliveTab(builder: (_) => _buildNewsTab()),
      KeepAliveTab(
        builder: (_) =>
            _buildFeed(_followingPosts, _followingController, false),
      ),
    ];
  }

  Future<void> _handleTabTap(int index) async {
    if (index == 1 || index == 2) {
      final ok = await _ensureMonetizedConsent();
      if (!ok) {
        // Force back to For You tab on cancel.
        _tabController.index = 0;
        setState(() {});
        return;
      }
    }
    setState(() {});
  }

  Future<bool> _ensureMonetizedConsent() async {
    if (_monetizedAccepted) return true;
    if (!mounted) return false;
    final theme = Theme.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          title: const Text('Monetized videos'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'All videos in this section are monetized. Watching short ads unlocks each video feed.',
              ),
              SizedBox(height: 8),
              Text('Part of the ad revenue supports video creators.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Accept & Continue'),
            ),
          ],
        );
      },
    );
    if (result == true) {
      _monetizedAccepted = true;
      return true;
    }
    return false;
  }

  Widget _buildWatchTab() {
    // Watch tab: horizontal/standard videos only.
    final videoPosts = _forYouPosts
        .where((p) => _isVideoPost(p) && !_isReelPost(p))
        .toList();
    return _buildVideoList(videoPosts);
  }

  Widget _buildLiveTab() {
    return LiveScreen(isGuest: _isGuest);
  }

  bool _isVideoPost(Post post) {
    final kind = post.kind?.toLowerCase() ?? '';
    if (kind.contains('video') || kind.contains('reel')) return true;
    if (post.videoUrl != null) return true;
    final media = _mediaByPostId[post.id] ?? const <String>[];
    return media.any(_isVideoUrl);
  }

  bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm');
  }

  bool _isReelPost(Post post) {
    final kind = post.kind?.toLowerCase();
    if (kind == null) return false;
    // Treat posts marked as reel/short as vertical reels.
    return kind.contains('reel') || kind.contains('short');
  }

  // Basic ranking: combine engagement, recency, and type preferences.
  double _scorePost(Post post) {
    final now = DateTime.now();
    final ageMinutes = now.difference(post.timestamp).inMinutes;
    final ageHours = ageMinutes <= 0 ? 0.0 : ageMinutes / 60.0;
    final recency = 1.0 / (1.0 + ageHours * 0.4); // newer posts get more weight

    final engagement =
        post.likes * 2 +
        post.comments * 3 +
        post.reposts * 4 +
        post.impressions * 0.1 +
        post.views * 0.3;

    final kindLower = (post.kind ?? '').toLowerCase();
    double typeBoost = 1.0;
    if (kindLower.contains('reel') || kindLower.contains('short')) {
      typeBoost = 1.2;
    } else if (kindLower.contains('video')) {
      typeBoost = 1.1;
    } else if (kindLower.contains('news') || kindLower.contains('blog')) {
      typeBoost = 1.05;
    }

    // Exploration boost: favour very new posts even with low engagement.
    final isVeryNew = ageMinutes >= 0 && ageMinutes < 60;
    final exploreBoost = isVeryNew ? 1.3 : 1.0;

    return (engagement + 1.0) * recency * typeBoost * exploreBoost;
  }

  // Build a mixed For You feed:
  // - Mostly text/image/news posts
  // - Occasionally mirror reels and watch videos based on spacing.
  List<Post> _buildForYouMixedFeed(List<Post> sortedPosts) {
    final textPosts = sortedPosts
        .where((p) => !_isVideoPost(p) || _isNewsPost(p))
        .toList();
    final watchPosts = sortedPosts
        .where((p) => _isVideoPost(p) && !_isReelPost(p) && !_isNewsPost(p))
        .toList();
    final reelPosts = sortedPosts
        .where((p) => _isVideoPost(p) && _isReelPost(p) && !_isNewsPost(p))
        .toList();

    final List<Post> result = [];
    int t = 0, w = 0, r = 0;

    while (t < textPosts.length) {
      result.add(textPosts[t++]);

      // After every 2 text posts, try to mirror 1 reel.
      if (t % 2 == 0 && r < reelPosts.length) {
        result.add(reelPosts[r++]);
      }

      // After every 3 text posts, try to mirror 1 watch video.
      if (t % 3 == 0 && w < watchPosts.length) {
        result.add(watchPosts[w++]);
      }
    }

    // Optionally sprinkle remaining reels/videos near the end.
    while (r < reelPosts.length && result.length % 4 == 0) {
      result.add(reelPosts[r++]);
    }
    while (w < watchPosts.length && result.length % 5 == 0) {
      result.add(watchPosts[w++]);
    }

    return result;
  }

  List<Post> _buildTrendingFeed(List<Post> sortedPosts) {
    final posts = List<Post>.from(sortedPosts);
    posts.sort((a, b) => b.totalEngagement.compareTo(a.totalEngagement));
    return posts;
  }

  Widget _buildReelsTab() {
    final reelsPosts = _forYouPosts
        .where((p) => _isVideoPost(p) && _isReelPost(p))
        .toList();
    return _buildReelsFeed(reelsPosts);
  }

  Widget _buildNewsTab() {
    final newsPosts = _forYouPosts.where(_isNewsPost).toList();

    return RefreshIndicator(
      onRefresh: () => _refreshFeed(true),
      child: ListView.builder(
        controller: _newsController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: EdgeInsets.zero,
        itemCount: newsPosts.isEmpty && !_isLoading
            ? 1
            : newsPosts.length + (_isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (newsPosts.isEmpty && !_isLoading) {
            return const SizedBox(
              height: 200,
              child: Center(child: Text('No news posts yet. Pull to refresh')),
            );
          }
          if (index >= newsPosts.length) {
            return _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF1DA1F2),
                      ),
                    ),
                  )
                : const SizedBox.shrink();
          }
          final post = newsPosts[index];
          return _buildPostCard(post, _mediaByPostId[post.id]);
        },
      ),
    );
  }

  bool _isNewsPost(Post post) {
    final kind = post.kind?.toLowerCase();
    if (kind == null) return false;
    return kind.contains('news') || kind.contains('blog');
  }

  Widget _buildPostCard(Post post, List<String>? media) {
    final isVideo = _isVideoPost(post);
    final isReel = _isReelPost(post);
    return PostCard(
      post: post,
      isGuest: _isGuest,
      onGuestAction: _showGuestPrompt,
      mediaUrls: media,
      authorId: _authorByPostId[post.id],
      showReelBadge: isReel,
      // Do not count impressions/views for videos/reels in feed;
      // their real view count comes from actual playback screens.
      trackImpressions: !isVideo,
      onOpenPost: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) {
              if (isReel && isVideo) {
                return ReelPlayer(
                  post: post,
                  isGuest: _isGuest,
                  onGuestAction: _showGuestPrompt,
                  authorId: _authorByPostId[post.id],
                  enableAds: !kIsWeb,
                );
              }
              if (isVideo) {
                return VideoDetailScreen(
                  post: post,
                  mediaUrls: media,
                  authorId: _authorByPostId[post.id],
                  isGuest: _isGuest,
                  onGuestAction: _showGuestPrompt,
                );
              }
              return PostDetailScreen(
                post: post,
                mediaUrls: media,
                authorId: _authorByPostId[post.id],
                isGuest: _isGuest,
                onGuestAction: _showGuestPrompt,
              );
            },
          ),
        );
      },
      onDeleted: () {
        setState(() {
          _forYouPosts.removeWhere((p) => p.id == post.id);
          _followingPosts.removeWhere((p) => p.id == post.id);
        });
      },
    );
  }

  Widget _buildVideoList(List<Post> posts) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktopGrid = constraints.maxWidth > 1100;
        if (!isDesktopGrid) {
          return ListView.builder(
            controller: _watchController,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.zero,
            itemCount: posts.isEmpty && !_isLoading
                ? 1
                : posts.length + (_isLoading ? 1 : 0),
            itemBuilder: (context, index) {
              if (posts.isEmpty && !_isLoading) {
                return const SizedBox(
                  height: 200,
                  child:
                      Center(child: Text('No videos yet. Pull to refresh')),
                );
              }
              if (index >= posts.length) {
                return _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF1DA1F2),
                          ),
                        ),
                      )
                    : const SizedBox.shrink();
              }
              final post = posts[index];
              if (post.videoUrl != null && post.videoUrl!.isNotEmpty) {
                return WatchVideoCard(
                  post: post,
                  mediaUrls: _mediaByPostId[post.id],
                  isGuest: _isGuest,
                  onGuestAction: _showGuestPrompt,
                  authorId: _authorByPostId[post.id],
                  enableAds: !kIsWeb,
                );
              }
              return _buildPostCard(post, _mediaByPostId[post.id]);
            },
          );
        }

        if (posts.isEmpty && !_isLoading) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('No videos yet. Pull to refresh'),
            ),
          );
        }

        return GridView.builder(
          controller: _watchController,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            // Slightly shorter than 16:9, but tall enough
            // to fit the video area + metadata without overflow.
            childAspectRatio: 16 / 11,
          ),
          itemCount: posts.length + (_isLoading ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= posts.length) {
              return _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF1DA1F2),
                      ),
                    )
                  : const SizedBox.shrink();
            }
            final post = posts[index];
            if (post.videoUrl != null && post.videoUrl!.isNotEmpty) {
              return WatchVideoCard(
                post: post,
                mediaUrls: _mediaByPostId[post.id],
                isGuest: _isGuest,
                onGuestAction: _showGuestPrompt,
                authorId: _authorByPostId[post.id],
                enableAds: !kIsWeb,
              );
            }
            return _buildPostCard(post, _mediaByPostId[post.id]);
          },
        );
      },
    );
  }

  Widget _buildReelsFeed(List<Post> posts) {
    if (posts.isEmpty && !_isLoading) {
      return const Center(child: Text('No reels yet. Pull to refresh'));
    }
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        // Only show reels with a video URL.
        if (post.videoUrl == null || post.videoUrl!.isEmpty) {
          return const Center(
            child: Text(
              'Video unavailable',
              style: TextStyle(color: Colors.white),
            ),
          );
        }
        return ReelPlayer(
          post: post,
          isGuest: _isGuest,
          onGuestAction: _showGuestPrompt,
          authorId: _authorByPostId[post.id],
          enableAds: !kIsWeb,
        );
      },
    );
  }

  Widget _buildFeed(
    List<Post> posts,
    ScrollController controller,
    bool isForYou,
  ) {
    final basePosts = List<Post>.from(posts);
    if (isForYou) {
      final seedSource = '${_currentUserId ?? 'guest'}-${DateTime.now().day}';
      final seed = seedSource.hashCode;
      basePosts.shuffle(Random(seed));
    } else {
      basePosts.sort((a, b) => _scorePost(b).compareTo(_scorePost(a)));
    }
    final visiblePosts = basePosts;
    return CustomScrollView(
      controller: controller,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        if (isForYou) const SliverToBoxAdapter(child: PendingUploadBanner()),
        if (isForYou)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 110,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _stories.length,
                itemBuilder: (context, index) {
                  final story = _stories[index];
                  final avatar = StoryAvatar(
                    story: story,
                    isCurrentUser: index == 0,
                  );
                  return GestureDetector(
                    onTap: () => _handleStoryTap(index),
                    child: avatar,
                  );
                },
              ),
            ),
          ),
        if (visiblePosts.isEmpty && !_isLoading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('No posts yet. Pull to refresh')),
          ),
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            if (index >= visiblePosts.length) {
              return _isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(
                          color: Color(0xFF1DA1F2),
                        ),
                      ),
                    )
                  : const SizedBox.shrink();
            }
            final post = visiblePosts[index];
            // Insert a native ad starting after the 2nd item, then every 3 posts (2,5,8,...).
            final shouldShowNative =
                isForYou && index >= 1 && ((index - 1) % 3 == 0);
            if (shouldShowNative) {
              return Column(
                children: [
                  _buildNativeAdTile(),
                  _buildPostCard(post, _mediaByPostId[post.id]),
                ],
              );
            }
            return _buildPostCard(post, _mediaByPostId[post.id]);
          }, childCount: visiblePosts.length + (_isLoading ? 1 : 0)),
        ),
      ],
    );
  }

  Widget _buildNativeAdTile() {
    if (kIsWeb) return const SizedBox.shrink();
    return const _NativeAdSlot(height: 320);
  }

  Future<void> _handleStoryTap(int index) async {
    if (index == 0) {
      final user = await AppwriteService.getCurrentUser();
      if (user == null) {
        _showGuestPrompt();
        return;
      }
      _showStoryOptions();
      return;
    }
    final user = await AppwriteService.getCurrentUser();
    if (!mounted) return;
    if (user == null) {
      _showGuestPrompt();
      return;
    }
    if (_isGuest) {
      setState(() => _isGuest = false);
    }
    if (index >= _stories.length) return;
    final story = _stories[index];
    StatusUpdate? statusMatch;
    for (final candidate in _statusUpdates) {
      if (candidate.id == story.id) {
        statusMatch = candidate;
        break;
      }
    }
    final status =
        statusMatch ??
        StoryManager.stories.value.firstWhere(
          (s) => s.id == story.id,
          orElse: () => StoryManager.stories.value.first,
        );
    status.isViewed = true;
    StoryManager.markViewed(status.id);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StatusViewerScreen(status: status)),
    );
  }

  void _showStoryOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose photo from gallery'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickStory(ImageSource.gallery, video: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library),
                title: const Text('Choose video from gallery'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickStory(ImageSource.gallery, video: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take photo'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickStory(ImageSource.camera, video: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text('Record video'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickStory(ImageSource.camera, video: true);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickStory(ImageSource source, {required bool video}) async {
    try {
      final XFile? file = video
          ? await _storyPicker.pickVideo(
              source: source,
              maxDuration: const Duration(seconds: 60),
            )
          : await _storyPicker.pickImage(source: source);
      if (file == null) return;
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StoryPublishScreen(media: file)),
      );
    } catch (_) {}
  }

  void _onScroll(ScrollController controller, bool isForYou) {
    if (controller.position.pixels >=
            controller.position.maxScrollExtent - 200 &&
        !_isLoading) {
      _loadMore(isForYou);
    }
  }

  Future<void> _refreshFeed(bool isForYou) async {
    setState(() {
      if (isForYou) {
        _forYouPosts.clear();
        _forYouCursor = null;
        FeedCache.clearForYou();
      } else {
        _followingPosts.clear();
        _followingCursor = null;
        FeedCache.clearFollowing();
      }
    });
    await _loadMore(isForYou);
    if (isForYou && _forYouPosts.length < 5) {
      await _loadMore(true);
    }
    if (!isForYou && _followingPosts.length < 5) {
      await _loadMore(false);
    }
  }

  Future<void> _loadMore(bool isForYou) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final fetchLimit = isForYou
          ? (_forYouCursor == null ? 20 : 10)
          : (_followingCursor == null ? 20 : 10);
      final aw.RowList docsList = isForYou
          ? await AppwriteService.fetchPosts(
              limit: fetchLimit,
              cursorId: _forYouCursor,
            )
          : await AppwriteService.fetchPostsByUserIds(
              _followingIds,
              limit: fetchLimit,
              cursorId: _followingCursor,
            );
      final List<aw.Row> docs = docsList.rows;
      final mapped = <Post>[];
      for (final d in docs) {
        final data = d.data;
        final List<String> rawMedia = data['mediaUrls'] is List
            ? (data['mediaUrls'] as List)
                  .map((item) => item.toString())
                  .toList()
            : [];
        _authorByPostId[d.$id] = data['userId'] as String? ?? '';
        final kind =
            (data['postType'] ?? data['type'] ?? data['category']) as String?;
        final title = data['title'] as String?;
        final thumbnailUrl = data['thumbnailUrl'] as String?;
        final kindLower = (kind ?? '').toLowerCase();
        final bool isVideoKind =
            kindLower.contains('video') || kindLower.contains('reel');

        String? videoUrl;
        String? firstImage;
        List<String> mediaForUi;

        if (isVideoKind && rawMedia.isNotEmpty) {
          final first = rawMedia.first;
          videoUrl =
              (first.startsWith('http://') || first.startsWith('https://'))
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
        mapped.add(
          Post(
            id: d.$id,
            username: data['username'] as String? ?? 'No Name',
            userAvatar: data['userAvatar'] as String? ?? '',
            content: data['content'] as String? ?? '',
            // Prefer Appwrite system $createdAt for stable time,
            // fall back to custom column or now if missing.
            timestamp:
                DateTime.tryParse(d.$createdAt) ??
                (data['createdAt'] != null
                    ? DateTime.tryParse(data['createdAt'] as String? ?? '') ??
                          DateTime.now()
                    : DateTime.now()),
            likes: data['likes'] as int? ?? 0,
            comments: data['comments'] as int? ?? 0,
            reposts: data['reposts'] as int? ?? 0,
            impressions: data['impressions'] as int? ?? 0,
            views: data['views'] as int? ?? 0,
            textBgColor: data['textBgColor'] as int?,
            imageUrl: firstImage,
            videoUrl: videoUrl,
            kind: kind,
            title: title,
            thumbnailUrl: thumbnailUrl,
            sourcePostId: data['sourcePostId'] as String?,
            sourceUserId: data['sourceUserId'] as String?,
            sourceUsername: data['sourceUsername'] as String?,
          ),
        );
      }

      // For following feed, also merge repost events (mirror behavior)
      if (!isForYou && _followingIds.isNotEmpty) {
        final repostRows = await AppwriteService.fetchRepostsByUserIds(
          _followingIds,
          limit: 20,
        );
        for (final r in repostRows.rows) {
          final rData = r.data;
          final postId = rData['postId'] as String?;
          final userId = rData['userId'] as String?;
          if (postId == null || userId == null) continue;
          try {
            final original = await AppwriteService.getRow(
              AppwriteService.postsCollectionId,
              postId,
            );
            final data = original.data;
            final List<String> rawMedia = data['mediaUrls'] is List
                ? (data['mediaUrls'] as List)
                      .map((item) => item.toString())
                      .toList()
                : [];
            final kind =
                (data['postType'] ?? data['type'] ?? data['category'])
                    as String?;
            final title = data['title'] as String?;
            final thumbnailUrl = data['thumbnailUrl'] as String?;
            final kindLower = (kind ?? '').toLowerCase();
            final bool isVideoKind =
                kindLower.contains('video') || kindLower.contains('reel');

            String? videoUrl;
            String? firstImage;
            List<String> mediaForUi;

            if (isVideoKind && rawMedia.isNotEmpty) {
              videoUrl = rawMedia.first;
              firstImage = thumbnailUrl?.isNotEmpty == true
                  ? thumbnailUrl
                  : (rawMedia.length > 1 ? rawMedia[1] : null);
              mediaForUi = firstImage != null
                  ? <String>[firstImage]
                  : <String>[];
            } else {
              firstImage = thumbnailUrl?.isNotEmpty == true
                  ? thumbnailUrl
                  : (rawMedia.isNotEmpty ? rawMedia.first : null);
              mediaForUi = rawMedia;
            }

            _mediaByPostId[postId] = mediaForUi;
            _authorByPostId[postId] = data['userId'] as String? ?? '';

            // Reposter username is not stored in repost row; fall back to userId.
            final reposterName = rData['username'] as String? ?? userId;

            mapped.add(
              Post(
                id: postId,
                username: data['username'] as String? ?? 'No Name',
                userAvatar: data['userAvatar'] as String? ?? '',
                content: data['content'] as String? ?? '',
                timestamp: rData['createdAt'] != null
                    ? DateTime.tryParse(rData['createdAt'] as String? ?? '') ??
                          DateTime.now()
                    : DateTime.now(),
                likes: data['likes'] as int? ?? 0,
                comments: data['comments'] as int? ?? 0,
                reposts: data['reposts'] as int? ?? 0,
                impressions: data['impressions'] as int? ?? 0,
                views: data['views'] as int? ?? 0,
                textBgColor: data['textBgColor'] as int?,
                imageUrl: firstImage,
                videoUrl: videoUrl,
                kind: kind,
                title: title,
                thumbnailUrl: thumbnailUrl,
                sourcePostId: postId,
                sourceUserId: userId,
                sourceUsername: reposterName,
              ),
            );
          } catch (_) {
            continue;
          }
        }
      }

      setState(() {
        final list = isForYou ? _forYouPosts : _followingPosts;
        list.addAll(mapped);
        if (docs.isNotEmpty) {
          if (isForYou) {
            _forYouCursor = docs.last.$id;
            FeedCache.forYouCursor = _forYouCursor;
          } else {
            _followingCursor = docs.last.$id;
            FeedCache.followingCursor = _followingCursor;
          }
        }
        // Persist caches
        FeedCache.forYouPosts = _forYouPosts;
        FeedCache.followingPosts = _followingPosts;
        FeedCache.mediaByPostId = _mediaByPostId;
        FeedCache.authorByPostId = _authorByPostId;
      });
      final bool needsExtraFetch =
          isForYou && _forYouPosts.length < 100 && docs.isNotEmpty;
      if (needsExtraFetch) {
        await _loadMore(isForYou);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showGuestPrompt() {
    showDialog(context: context, builder: (_) => const GuestPrompt());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _forYouController.dispose();
    _followingController.dispose();
    _watchController.dispose();
    _newsController.dispose();
    _postsSub?.close();
    StoryManager.stories.removeListener(_storiesListener);
    super.dispose();
  }
}

class _NativeAdSlot extends StatefulWidget {
  final double height;
  const _NativeAdSlot({required this.height});

  @override
  State<_NativeAdSlot> createState() => _NativeAdSlotState();
}

class _NativeAdSlotState extends State<_NativeAdSlot> {
  NativeAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ad = NativeAd(
      adUnitId: AdHelper.native,
      factoryId: 'cardNative',
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: AdWidget(ad: _ad!),
    );
  }
}
