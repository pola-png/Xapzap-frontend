import 'dart:async';

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../models/post.dart';
import '../screens/comment_screen.dart';
import '../services/appwrite_service.dart';
import '../services/storage_service.dart';
import '../utils/share_utils.dart';
import '../services/ad_helper.dart';
import '../services/ad_frequency_service.dart';

class ReelPlayer extends StatefulWidget {
  final Post post;
  final bool isGuest;
  final VoidCallback? onGuestAction;
  final String? authorId;
  final bool enableAds;

  const ReelPlayer({
    super.key,
    required this.post,
    this.isGuest = false,
    this.onGuestAction,
    this.authorId,
    this.enableAds = true,
  });

  @override
  State<ReelPlayer> createState() => _ReelPlayerState();
}

class _ReelPlayerState extends State<ReelPlayer> {
  VideoPlayerController? _controller;
  Future<void>? _initFuture;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _isLiked = false;
  bool _hasReposted = false;
  int _likeCount = 0;
  int _commentCount = 0;
  int _repostCount = 0;
  int _impressionCount = 0;
  int _shareCount = 0;
  Timer? _hideControlsTimer;
  bool _countedView = false;
  RewardedAd? _rewardedAd;
  bool _rewardedLoading = false;
  NativeAd? _nativeAd;
  bool _nativeLoaded = false;
  bool _nativeLoading = false;
  bool _showNativeOverlay = false;
  bool _canDismissNative = false;
  bool _showRewardedOverlay = false;
  DateTime? _lastTick;
  bool get _adsEnabled =>
      widget.enableAds && !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _likeCount = widget.post.likes;
    _commentCount = widget.post.comments;
    _repostCount = widget.post.reposts;
    _impressionCount = widget.post.impressions;
    _shareCount = 0;

    final url = widget.post.videoUrl;
    if (url != null && url.isNotEmpty) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(url));
      _controller!.setLooping(true);
      _initFuture = _controller!.initialize().then((_) async {
        _controller!.addListener(_onVideoTick);
        if (mounted) setState(() {});
      });
    }
    if (_adsEnabled) {
      _loadRewarded();
      _prefetchNative();
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    _nativeAd?.dispose();
    _rewardedAd?.dispose();
    super.dispose();
  }

  Future<String?> _resolveAvatar(String raw) async {
    if (raw.isEmpty) return null;
    if (raw.contains('cloud.appwrite.io') || raw.startsWith('http')) {
      return raw;
    }
    try {
      return await WasabiService.getSignedUrl(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: Stack(
        children: [
          Positioned.fill(child: _buildVideo()),
          // Gradient overlay for text legibility
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Right side vertical reactions (like Watch reaction section, but stacked)
          Positioned(
            right: 12,
            bottom: 80,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildReactionButton(
                  icon: _isLiked ? LucideIcons.heart : LucideIcons.heart,
                  iconColor: _isLiked ? const Color(0xFFFF2D55) : Colors.white,
                  count: _likeCount,
                  onTap: _toggleLike,
                ),
                const SizedBox(height: 18),
                _buildReactionButton(
                  icon: LucideIcons.messageCircle,
                  iconColor: Colors.white,
                  count: _commentCount,
                  onTap: _openComments,
                ),
                const SizedBox(height: 18),
                _buildReactionButton(
                  icon: LucideIcons.repeat2,
                  iconColor: _hasReposted ? const Color(0xFF1DA1F2) : Colors.white,
                  count: _repostCount,
                  onTap: _repostPost,
                ),
                const SizedBox(height: 18),
                _buildReactionButton(
                  icon: LucideIcons.share2,
                  iconColor: Colors.white,
                  count: _shareCount,
                  onTap: _sharePost,
                ),
                const SizedBox(height: 18),
                _buildReactionButton(
                  icon: LucideIcons.barChart2,
                  iconColor: Colors.white,
                  count: _impressionCount,
                  label: 'Views',
                  onTap: () {},
                ),
              ],
            ),
          ),
          // Bottom user + caption
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FutureBuilder<String?>(
                  future: _resolveAvatar(widget.post.userAvatar),
                  builder: (context, snap) {
                    final url = snap.data;
                    if (url == null || url.isEmpty) {
                      return CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.grey[300],
                        child: const Icon(Icons.person, color: Colors.grey),
                      );
                    }
                    return CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.grey[300],
                      backgroundImage: NetworkImage(url),
                    );
                  },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.post.username,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (widget.post.content.isNotEmpty)
                        Text(
                          widget.post.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideo() {
    if (_controller == null) {
      return const Center(
        child: Text('Video unavailable'),
      );
    }
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done || !_controller!.value.isInitialized) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        // Force vertical 9:16-ish display, letterboxing if needed.
        final size = _controller!.value.size;
        final isVertical = size.height >= size.width;
        final aspect = isVertical ? (9 / 16) : _controller!.value.aspectRatio;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() => _showControls = true);
            _scheduleHideControls();
          },
          onDoubleTap: _togglePlay,
          child: Center(
            child: AspectRatio(
              aspectRatio: aspect,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoPlayer(_controller!),
                  // Very subtle center play/pause overlay
                  AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      // Visual only; taps are handled by the parent GestureDetector.
                      ignoring: true,
                      child: Center(
                        child: Icon(
                          _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                          size: 48,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ),
                  ),
                  // Bottom-right duration text
                  Positioned(
                    right: 12,
                    bottom: 8,
                    child: Text(
                      _formatDuration(
                        _controller!.value.position,
                        _controller!.value.duration,
                      ),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
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
                                                    child: AdWidget(ad: _nativeAd!),
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
                                            onPressed: _canDismissNative
                                                ? _closeNativeOverlay
                                                : null,
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
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReactionButton({
    required IconData icon,
    required Color iconColor,
    required int count,
    required VoidCallback onTap,
    String? label,
  }) {
    return Column(
      children: [
        InkResponse(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          radius: 28,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.25),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              count.toString(),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            if (label != null) ...[
              const SizedBox(width: 2),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ],
          ],
        ),
      ],
    );
  }

  void _togglePlay() async {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      await _controller!.pause();
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _showControls = true;
        });
      }
      _hideControlsTimer?.cancel();
    } else {
      await _playWithGate();
    }
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
    if (!_adsEnabled) {
      await _startPlayback();
      return;
    }
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
      setState(() {
        _isPlaying = true;
        _showControls = true;
      });
      if (!_countedView) {
        _countedView = true;
        _impressionCount += 1;
        AppwriteService.incrementPostImpressions(widget.post.id, 1);
      }
      _scheduleHideControls();
    }
  }

  void _loadRewarded() {
    if (!_adsEnabled || _rewardedLoading || _rewardedAd != null) return;
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

  Future<void> _showRewarded() async {
    if (!_adsEnabled) {
      await _startPlayback();
      return;
    }
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
    if (!_adsEnabled || !Platform.isAndroid) {
      await _startPlayback();
      return;
    }
    if (!_nativeLoaded || _nativeAd == null) {
      await _startPlayback();
      return;
    }
    setState(() {
      _showNativeOverlay = true;
      _canDismissNative = true;
    });
  }

  void _closeNativeOverlay() {
    setState(() {
      _showNativeOverlay = false;
    });
    _startPlayback();
  }

  void _prefetchNative() {
    if (!_adsEnabled || !Platform.isAndroid) return;
    if (_nativeLoading || _nativeAd != null) return;
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
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _nativeAd = null;
            _nativeLoading = false;
          });
        },
      ),
    )..load();
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
    });
    try {
      if (targetLike) {
        await AppwriteService.likePost(widget.post.id);
      } else {
        await AppwriteService.unlikePost(widget.post.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLiked = !targetLike;
        _likeCount = previousCount;
      });
    }
  }

  void _openComments() {
    if (widget.isGuest) {
      widget.onGuestAction?.call();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CommentScreen(post: widget.post),
      ),
    );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(targetRepost ? 'Reel reposted' : 'Repost removed'),
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

  void _sharePost() {
    setState(() => _shareCount++);
    AppwriteService.incrementPostShares(widget.post.id, 1);
    ShareUtils.sharePost(
      postId: widget.post.id,
      username: widget.post.username,
      content: widget.post.content,
    );
  }

  String _formatDuration(Duration position, Duration total) {
    String two(int n) => n.toString().padLeft(2, '0');
    final posMinutes = two(position.inMinutes.remainder(60));
    final posSeconds = two(position.inSeconds.remainder(60));
    final totMinutes = two(total.inMinutes.remainder(60));
    final totSeconds = two(total.inSeconds.remainder(60));
    return '$posMinutes:$posSeconds / $totMinutes:$totSeconds';
  }
}
