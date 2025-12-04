import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;
import 'package:video_player/video_player.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../models/post.dart';
import '../widgets/post_card.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/appwrite_service.dart';
import '../services/storage_service.dart';
import '../widgets/voice_recorder.dart';
import '../services/ad_helper.dart';
import '../services/ad_frequency_service.dart';
import '../widgets/watch_video_card.dart';
import '../services/feed_cache.dart';

class VideoDetailScreen extends StatefulWidget {
  final Post post;
  final List<String>? mediaUrls;
  final String? authorId;
  final bool isGuest;
  final VoidCallback? onGuestAction;
  final Duration? initialPosition;
  final bool autoPlay;

  const VideoDetailScreen({
    super.key,
    required this.post,
    this.mediaUrls,
    this.authorId,
    this.isGuest = false,
    this.onGuestAction,
    this.initialPosition,
    this.autoPlay = true,
  });

  @override
  State<VideoDetailScreen> createState() => _VideoDetailScreenState();
}

class _VideoDetailScreenState extends State<VideoDetailScreen> {
  VideoPlayerController? _controller;
  Future<void>? _initFuture;
  bool _isPlaying = false;
  bool _isMuted = false;
  bool _showControls = true;
  bool _isFullscreen = false;
  Timer? _hideControlsTimer;
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  bool _isVoiceMode = false;
  String? _currentUserId;
  String? _currentUserAvatarUrl;
  RewardedAd? _rewardedAd;
  bool _rewardedLoading = false;
  NativeAd? _nativeAd;
  bool _nativeLoaded = false;
  bool _nativeLoading = false;
  NativeAd? _inlineNativeAd;
  bool _inlineNativeLoaded = false;
  bool _inlineNativeLoading = false;
  bool _showNativeOverlay = false;
  bool _canDismissNative = false;
  bool _showRewardedOverlay = false;
  Timer? _nativeMinTimer;
  DateTime? _lastTick;

  @override
  void initState() {
    super.initState();
    // Allow this screen to rotate into landscape for a better video experience.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _loadCurrentUser();

    final videoUrl = widget.post.videoUrl;
    if (videoUrl != null && videoUrl.isNotEmpty) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      _initFuture = _controller!.initialize().then((_) {
        _controller!.addListener(_onVideoTick);
        if (widget.initialPosition != null) {
          _controller!.seekTo(widget.initialPosition!);
        }
        if (mounted) setState(() {});
      });
    }
    _loadRewarded();
    _loadInlineNative();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _nativeMinTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Restore the app back to portrait when leaving the video detail screen.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    _commentController.dispose();
    _commentFocusNode.dispose();
    _nativeAd?.dispose();
    _inlineNativeAd?.dispose();
    _rewardedAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final showOnlyVideo = _isFullscreen || (isLandscape && !kIsWeb);
    final onSurface = theme.colorScheme.onSurface;
    final surface = theme.colorScheme.surface;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: showOnlyVideo
          ? null
          : AppBar(
              backgroundColor: surface,
              elevation: 0,
              iconTheme: IconThemeData(color: onSurface),
              title: Text(
                widget.post.title?.isNotEmpty == true ? widget.post.title! : 'Video',
                style: TextStyle(color: onSurface),
              ),
            ),
      body: showOnlyVideo
          ? Center(child: _buildVideoPlayer(theme))
          : LayoutBuilder(
              builder: (context, constraints) {
                final isDesktopWide = kIsWeb && constraints.maxWidth > 1100;
                if (isDesktopWide) {
                  return Column(
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                children: [
                                  _buildVideoPlayer(theme),
                                  Expanded(child: _buildMetaSection(theme)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: constraints.maxWidth * 0.32,
                              child: _buildSuggestionsSidebar(theme),
                            ),
                          ],
                        ),
                      ),
                      _buildCommentInput(),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _buildVideoPlayer(theme),
                          Expanded(child: _buildMetaSection(theme)),
                        ],
                      ),
                    ),
                    _buildCommentInput(),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildMetaSection(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (widget.post.title?.trim().isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                widget.post.title!.trim(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (widget.post.content.trim().isNotEmpty)
            _buildDescriptionPreview(theme),
          // Use a Post copy with no image so we don't show the thumbnail again.
          PostCard(
            post: _copyWithoutImage(widget.post),
            isGuest: widget.isGuest,
            onGuestAction: widget.onGuestAction,
            mediaUrls: const <String>[],
            authorId: widget.authorId,
            onOpenPost: null,
            isDetail: true,
            // Hide in-card video description; we show
            // a separate tappable preview below.
            showVideoMeta: false,
          ),
          _buildInlineNativeAd(theme),
        ],
      ),
    );
  }

  Widget _buildDescriptionPreview(ThemeData theme) {
    final description = widget.post.content.trim();
    if (description.isEmpty) return const SizedBox.shrink();

    const maxChars = 100;
    var snippet = description;
    var truncated = false;
    if (snippet.length > maxChars) {
      snippet = snippet.substring(0, maxChars);
      truncated = true;
    }

    return InkWell(
      onTap: _openDescriptionSheet,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Description',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    snippet + (truncated ? '...' : ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.expand_less, // small hint that it expands
                  size: 16,
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayer(ThemeData theme) {
    if (_controller == null) {
      return const SizedBox(
        height: 240,
        child: Center(
          child: Text(
            'Video not available',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done || !_controller!.value.isInitialized) {
          return const SizedBox(
            height: 240,
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }
        final aspect = _controller!.value.aspectRatio == 0 ? 16 / 9 : _controller!.value.aspectRatio;
        return Stack(
          alignment: Alignment.center,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _showControls = !_showControls;
                });
                if (_showControls) {
                  _scheduleHideControls();
                } else {
                  _hideControlsTimer?.cancel();
                }
              },
              child: AspectRatio(
                aspectRatio: aspect,
                child: VideoPlayer(_controller!),
              ),
            ),
            // Top icons: fullscreen (left) and speaker (right), auto-hidden.
            Positioned(
              top: 12,
              left: 12,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: _buildControlButton(
                    icon: _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    onTap: () {
                      setState(() => _isFullscreen = !_isFullscreen);
                      if (_isFullscreen) {
                        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
                      } else {
                        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                      }
                      _scheduleHideControls();
                    },
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: _buildControlButton(
                    icon: _isMuted ? Icons.volume_off : Icons.volume_up,
                    onTap: () {
                      if (_controller == null) return;
                      setState(() {
                        _isMuted = !_isMuted;
                        _controller!.setVolume(_isMuted ? 0.0 : 1.0);
                      });
                      _scheduleHideControls();
                    },
                  ),
                ),
              ),
            ),
            // Center controls: back / play-pause / forward, auto-hidden in the middle.
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildControlButton(
                        icon: Icons.replay_10,
                        onTap: () {
                          _seekRelative(const Duration(seconds: -10));
                          _scheduleHideControls();
                        },
                      ),
                      const SizedBox(width: 40),
                      _buildControlButton(
                        icon: _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                        onTap: () async {
                          if (_controller == null) return;
                          if (_controller!.value.isPlaying) {
                            await _controller!.pause();
                            if (mounted) setState(() => _isPlaying = false);
                            _hideControlsTimer?.cancel();
                          } else {
                            await _playWithGate();
                          }
                        },
                      ),
                      const SizedBox(width: 40),
                      _buildControlButton(
                        icon: Icons.forward_10,
                        onTap: () {
                          _seekRelative(const Duration(seconds: 10));
                          _scheduleHideControls();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Bottom duration + progress, auto-hidden and pinned to the bottom of the video.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 16, bottom: 6),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            _formatDuration(
                              _controller!.value.position,
                              _controller!.value.duration,
                            ),
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                      VideoProgressIndicator(
                        _controller!,
                        allowScrubbing: true,
                        padding: const EdgeInsets.only(bottom: 4),
                        colors: const VideoProgressColors(
                          playedColor: Colors.white,
                          bufferedColor: Colors.white54,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_showRewardedOverlay || _showNativeOverlay)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.7),
                  child: Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final screenH = MediaQuery.of(context).size.height;
                        final maxH = constraints.maxHeight.isFinite ? constraints.maxHeight : screenH;
                        final usableH = (maxH - 48).clamp(120.0, maxH);
                        final adHeight = (usableH * 0.6).clamp(120.0, usableH);
                        return Material(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    height: adHeight,
                                    width: double.infinity,
                                    child: _showRewardedOverlay
                                        ? const Center(
                                            child: Text(
                                              'Ad playing...',
                                              style: TextStyle(color: Colors.white),
                                            ),
                                          )
                                        : (_nativeLoaded && _nativeAd != null
                                            ? ClipRRect(
                                                borderRadius: BorderRadius.circular(8),
                                                child: AdWidget(key: UniqueKey(), ad: _nativeAd!),
                                              )
                                            : const SizedBox.shrink()),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Ad playing... video will resume',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  const SizedBox(height: 8),
                                  if (!_showRewardedOverlay)
                                    ElevatedButton(
                                      onPressed: _canDismissNative ? _closeNativeOverlay : null,
                                      child: const Text('Continue'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _openDescriptionSheet() {
    final theme = Theme.of(context);
    final description = widget.post.content.trim();
    if (description.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.5,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Description',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: const EdgeInsets.all(6.0),
          child: Icon(icon, color: Colors.white, size: 35),
        ),
      ),
    );
  }

  void _seekRelative(Duration offset) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final current = _controller!.value.position;
    final target = current + offset;
    // Manually clamp because some SDKs don't support Duration.clamp.
    final total = _controller!.value.duration;
    Duration clamped;
    if (target < Duration.zero) {
      clamped = Duration.zero;
    } else if (target > total) {
      clamped = total;
    } else {
      clamped = target;
    }
    _controller!.seekTo(clamped);
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (kIsWeb) {
      if (!_showControls) {
        setState(() => _showControls = true);
      }
      return;
    }
    if (!_isPlaying) {
      setState(() => _showControls = true);
      return;
    }
    setState(() => _showControls = true);
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _onVideoTick() {
    if (!mounted || _controller == null) return;
    final now = DateTime.now();
    if (_lastTick != null && now.difference(_lastTick!).inMilliseconds < 500) return;
    _lastTick = now;
    setState(() {});
  }

  Future<void> _playWithGate() async {
    if (_controller == null) return;
    final needsRewarded = await AdFrequencyService.shouldShowRewarded(widget.post.id);
    if (needsRewarded) {
      await _showRewarded();
    } else {
      await _showNative();
    }
  }

  Future<void> _startPlayback() async {
    if (_controller == null) return;
    await _controller!.play();
    if (mounted) {
      setState(() => _isPlaying = true);
      _scheduleHideControls();
    }
  }

  void _loadRewarded() {
    if (_rewardedLoading || _rewardedAd != null) return;
    _rewardedLoading = true;
    RewardedAd.load(
      adUnitId: AdHelper.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _rewardedLoading = false;
        },
        onAdFailedToLoad: (_) {
          _rewardedAd = null;
          _rewardedLoading = false;
        },
      ),
    );
  }

  void _loadInlineNative() {
    if (_inlineNativeLoading || _inlineNativeAd != null) return;
    if (kIsWeb || !Platform.isAndroid) return;
    _inlineNativeLoading = true;
    _inlineNativeAd = NativeAd(
      adUnitId: AdHelper.native,
      factoryId: 'cardNative',
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() {
            _inlineNativeLoaded = true;
            _inlineNativeLoading = false;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _inlineNativeAd = null;
            _inlineNativeLoaded = false;
            _inlineNativeLoading = false;
          });
        },
      ),
    )..load();
  }

  Future<void> _showRewarded() async {
    final ad = _rewardedAd;
    if (ad == null) {
      _loadRewarded();
      await _startPlayback();
      return;
    }
    setState(() => _showRewardedOverlay = true);
    final completer = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        _loadRewarded();
        setState(() => _showRewardedOverlay = false);
        completer.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _rewardedAd = null;
        _loadRewarded();
        setState(() => _showRewardedOverlay = false);
        completer.complete();
      },
    );
    ad.show(onUserEarnedReward: (_, reward) {});
    await completer.future;
    await AdFrequencyService.markRewarded(widget.post.id);
    setState(() => _showRewardedOverlay = false);
    await _startPlayback();
  }

  Future<void> _showNative() async {
    if (kIsWeb || !Platform.isAndroid) {
      await _startPlayback();
      return;
    }
    if (_nativeLoading) return;
    _nativeLoading = true;
    _nativeLoaded = false;
    _nativeAd?.dispose();
    _nativeAd = NativeAd(
      adUnitId: AdHelper.native,
      factoryId: 'cardNative',
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() {
            _nativeLoaded = true;
            _nativeLoading = false;
            _showNativeOverlay = true;
            _canDismissNative = false;
          });
          _nativeMinTimer?.cancel();
          _nativeMinTimer = Timer(const Duration(seconds: 2), () {
            if (!mounted) return;
            setState(() => _canDismissNative = true);
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _nativeAd = null;
            _nativeLoading = false;
            _showNativeOverlay = false;
          });
          _startPlayback();
        },
      ),
    )..load();
    setState(() {
      _showNativeOverlay = true;
      _canDismissNative = false;
    });
  }

  void _closeNativeOverlay() {
    setState(() {
      _showNativeOverlay = false;
    });
    _startPlayback();
  }

  Widget _buildInlineNativeAd(ThemeData theme) {
    if (kIsWeb || !Platform.isAndroid) return const SizedBox.shrink();
    if (_inlineNativeAd == null && !_inlineNativeLoading) {
      _loadInlineNative();
    }
    if (_inlineNativeAd == null || !_inlineNativeLoaded) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant, width: 0.5),
        ),
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 240,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AdWidget(key: UniqueKey(), ad: _inlineNativeAd!),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionsSidebar(ThemeData theme) {
    final candidates = FeedCache.forYouPosts
        .where((p) =>
            p.id != widget.post.id &&
            p.videoUrl != null &&
            p.videoUrl!.isNotEmpty)
        .toList();
    if (candidates.isEmpty) {
      return const SizedBox.shrink();
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
      itemCount: candidates.length,
      itemBuilder: (context, index) {
        final post = candidates[index];
        final media = FeedCache.mediaByPostId[post.id];
        final authorId = FeedCache.authorByPostId[post.id];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: WatchVideoCard(
            post: post,
            mediaUrls: media,
            isGuest: widget.isGuest,
            onGuestAction: widget.onGuestAction,
            authorId: authorId,
            // Avoid extra ads inside sidebar suggestions.
            enableAds: false,
          ),
        );
      },
    );
  }

  Future<void> _loadCurrentUser() async {
    final user = await AppwriteService.getCurrentUser();
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _currentUserId = null;
        _currentUserAvatarUrl = null;
      });
      return;
    }
    final prof = await AppwriteService.getProfileByUserId(user.$id);
    String? avatar = prof?.data['avatarUrl'] as String?;
    if (avatar != null && avatar.isNotEmpty && !avatar.startsWith('http')) {
      try {
        avatar = await WasabiService.getSignedUrl(avatar);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _currentUserId = user.$id;
      _currentUserAvatarUrl = avatar;
    });
  }

  Widget _buildCommentInput() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = theme.scaffoldBackgroundColor;
    final inputFillColor = isDark ? const Color(0xFF111827) : Colors.grey[100];
    final textColor = theme.textTheme.bodyMedium?.color ?? Colors.black;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: bgColor,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.grey[200],
              backgroundImage: _currentUserAvatarUrl != null &&
                      _currentUserAvatarUrl!.isNotEmpty
                  ? NetworkImage(_currentUserAvatarUrl!)
                  : null,
              child: (_currentUserAvatarUrl == null ||
                      _currentUserAvatarUrl!.isEmpty)
                  ? const Icon(Icons.person, color: Colors.grey)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _isVoiceMode
                  ? VoiceRecorder(onRecorded: _handleVoiceRecorded)
                  : TextField(
                      controller: _commentController,
                      focusNode: _commentFocusNode,
                      decoration: InputDecoration(
                        hintText: 'Add a comment...',
                        hintStyle: TextStyle(color: textColor.withOpacity(0.6)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: inputFillColor,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      ),
                      style: TextStyle(color: textColor, fontSize: 16),
                      onSubmitted: _submitComment,
                    ),
            ),
            if (!_isVoiceMode) ...[
              IconButton(
                icon: const Icon(LucideIcons.mic, color: Color(0xFF1DA1F2)),
                onPressed: () {
                  if (_currentUserId == null || widget.isGuest) {
                    widget.onGuestAction?.call();
                    return;
                  }
                  setState(() => _isVoiceMode = true);
                },
              ),
              IconButton(
                icon: const Icon(LucideIcons.send, color: Color(0xFF1DA1F2)),
                onPressed: () => _submitComment(_commentController.text),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _submitComment(String text) async {
    final content = text.trim();
    if (content.isEmpty) return;
    if (widget.isGuest) {
      widget.onGuestAction?.call();
      return;
    }
    try {
      await AppwriteService.createComment(widget.post.id, content);
      await AppwriteService.incrementPostComments(widget.post.id, 1);
      if (!mounted) return;
      _commentController.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Comment posted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to comment: $e')));
    }
  }

  Future<void> _handleVoiceRecorded(String? path) async {
    setState(() => _isVoiceMode = false);
    if (path == null || _currentUserId == null) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final voiceUrl = await WasabiService.uploadVoiceComment(path, _currentUserId!);
      if (voiceUrl == null) return;

      await AppwriteService.createVoiceComment(widget.post.id, voiceUrl);
      await AppwriteService.incrementPostComments(widget.post.id, 1);

      if (!mounted) return;
      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Voice comment posted!')));
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Failed to post voice comment.')));
    }
  }

  String _formatDuration(Duration position, Duration total) {
    String two(int n) => n.toString().padLeft(2, '0');
    final posMinutes = two(position.inMinutes.remainder(60));
    final posSeconds = two(position.inSeconds.remainder(60));
    final totMinutes = two(total.inMinutes.remainder(60));
    final totSeconds = two(total.inSeconds.remainder(60));
    return '$posMinutes:$posSeconds / $totMinutes:$totSeconds';
  }

  Post _copyWithoutImage(Post original) {
    return Post(
      id: original.id,
      username: original.username,
      userAvatar: original.userAvatar,
      content: original.content,
      imageUrl: null,
      videoUrl: original.videoUrl,
      kind: original.kind,
      title: original.title,
      thumbnailUrl: original.thumbnailUrl,
      timestamp: original.timestamp,
      likes: original.likes,
      comments: original.comments,
      reposts: original.reposts,
      impressions: original.impressions,
      views: original.views,
      isLiked: original.isLiked,
      isReposted: original.isReposted,
      isSaved: original.isSaved,
    );
  }
}
