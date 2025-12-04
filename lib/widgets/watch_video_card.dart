import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;
import 'package:video_player/video_player.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../models/post.dart';
import '../screens/video_detail_screen.dart';
import '../services/appwrite_service.dart';
import '../services/ad_helper.dart';
import '../services/ad_frequency_service.dart';
import 'post_card.dart';

class WatchVideoCard extends StatefulWidget {
  final Post post;
  final List<String>? mediaUrls;
  final bool isGuest;
  final VoidCallback? onGuestAction;
  final String? authorId;
  final bool enableAds;

  const WatchVideoCard({
    super.key,
    required this.post,
    this.mediaUrls,
    this.isGuest = false,
    this.onGuestAction,
    this.authorId,
    this.enableAds = true,
  });

  @override
  State<WatchVideoCard> createState() => _WatchVideoCardState();
}

class _WatchVideoCardState extends State<WatchVideoCard> {
  VideoPlayerController? _controller;
  Future<void>? _initFuture;
  bool _isPlaying = false;
  bool _isMuted = false;
  bool _countedView = false;
  bool _showControls = true;
  Timer? _hideControlsTimer;
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
    final url = widget.post.videoUrl;
    if (url != null && url.isNotEmpty) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(url));
      _controller!.setLooping(true);
      _initFuture = _controller!.initialize().then((_) {
        _controller!.addListener(_onVideoTick);
        if (!mounted) return;
        setState(() {});
      });
      if (_adsEnabled) {
        _loadRewarded();
        _prefetchNative();
      }
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    _rewardedAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumb = (widget.mediaUrls != null && widget.mediaUrls!.isNotEmpty)
        ? widget.mediaUrls!.first
        : widget.post.thumbnailUrl;

    return GestureDetector(
      onTap: _openDetail,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildVideoArea(theme, thumb),
            // Reuse the same PostCard header + video meta + reactions as detail,
            // but clamp description to 1 line and route "See more" to the detail screen.
            PostCard(
              post: _copyWithoutImage(widget.post),
              isGuest: widget.isGuest,
              onGuestAction: widget.onGuestAction,
              mediaUrls: const <String>[],
              authorId: widget.authorId,
              trackImpressions: false,
              showViewsLabel: true,
              showVideoMeta: true,
              videoDescriptionMaxLines: 1,
              onVideoDescriptionTap: _openDetail,
              onOpenPost: _openDetail,
              isDetail: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoArea(ThemeData theme, String? thumb) {
    if (_controller == null || _initFuture == null) {
      if (thumb != null && thumb.isNotEmpty) {
        return AspectRatio(
          aspectRatio: 16 / 9,
          child: Image.network(
            thumb,
            fit: BoxFit.cover,
          ),
        );
      }
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done ||
            !_controller!.value.isInitialized) {
          if (thumb != null && thumb.isNotEmpty) {
            return AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                thumb,
                fit: BoxFit.cover,
              ),
            );
          }
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final aspect = _controller!.value.aspectRatio == 0
            ? 16 / 9
            : _controller!.value.aspectRatio;
        // Center overlay controls in the middle of the video and pin
        // duration/progress to the bottom.
        return Stack(
          alignment: Alignment.center,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _showControls = true;
                });
                _scheduleHideControls();
              },
              child: AspectRatio(
                aspectRatio: aspect,
                child: VideoPlayer(_controller!),
              ),
            ),
            // Top-right speaker icon, auto-hidden.
            Positioned(
              top: 8,
              right: 8,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: _buildControlButton(
                    icon: _isMuted ? Icons.volume_off : Icons.volume_up,
                    onTap: () {
                      _toggleMute();
                      _scheduleHideControls();
                    },
                  ),
                ),
              ),
            ),
            // Center controls: back / play-pause / forward, auto-hidden.
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
                      const SizedBox(width: 24),
                      _buildControlButton(
                        icon: _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                        onTap: () {
                          _togglePlay();
                          _scheduleHideControls();
                        },
                      ),
                      const SizedBox(width: 24),
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
            // Bottom duration + progress, auto-hidden and pinned to bottom.
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
                        padding: const EdgeInsets.only(right: 12, bottom: 4),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            _formatDuration(
                              _controller!.value.position,
                              _controller!.value.duration,
                            ),
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ),
                      ),
                      VideoProgressIndicator(
                        _controller!,
                        allowScrubbing: true,
                        padding: const EdgeInsets.only(bottom: 2),
                        colors: const VideoProgressColors(
                          playedColor: Colors.white,
                          bufferedColor: Colors.white54,
                          backgroundColor: Colors.black26,
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

  Widget _buildControlButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Icon(icon, color: Colors.white, size: 35),
        ),
      ),
    );
  }

  void _togglePlay() async {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      await _controller!.pause();
      if (mounted) setState(() => _isPlaying = false);
    } else {
      await _playWithGate();
    }
  }

  void _toggleMute() {
    if (_controller == null) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  void _incrementView() {
    if (_countedView) return;
    _countedView = true;
    AppwriteService.incrementPostImpressions(widget.post.id, 1);
  }

  void _openDetail() {
    Duration? position;
    bool wasPlaying = false;
    if (_controller != null && _controller!.value.isInitialized) {
      position = _controller!.value.position;
      wasPlaying = _controller!.value.isPlaying;
      _controller!.pause();
      _isPlaying = false;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoDetailScreen(
          post: widget.post,
          mediaUrls: widget.mediaUrls,
          authorId: widget.authorId,
          isGuest: widget.isGuest,
          onGuestAction: widget.onGuestAction,
          initialPosition: position,
          autoPlay: wasPlaying,
        ),
      ),
    );
  }

  Post _copyWithoutImage(Post original) {
    return Post(
      id: original.id,
      username: original.username,
      userAvatar: original.userAvatar,
      content: original.content,
      textBgColor: original.textBgColor,
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
    if (!_countedView) {
      _incrementView();
    }
    if (mounted) {
      setState(() => _isPlaying = true);
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

  String _formatDuration(Duration position, Duration total) {
    String two(int n) => n.toString().padLeft(2, '0');
    final posMinutes = two(position.inMinutes.remainder(60));
    final posSeconds = two(position.inSeconds.remainder(60));
    final totMinutes = two(total.inMinutes.remainder(60));
    final totSeconds = two(total.inSeconds.remainder(60));
    return '$posMinutes:$posSeconds / $totMinutes:$totSeconds';
  }
}
