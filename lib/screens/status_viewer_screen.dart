import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/status.dart';
import 'dart:async';
import 'package:xapzap/services/appwrite_service.dart';
import 'package:xapzap/services/crypto_service.dart';
import '../services/story_manager.dart';

class StatusViewerScreen extends StatefulWidget {
  final StatusUpdate status;

  const StatusViewerScreen({super.key, required this.status});

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen>
    with TickerProviderStateMixin {
  late final AnimationController _progressController;
  final TextEditingController _replyController = TextEditingController();
  int _currentIndex = 0;
  bool _isPaused = false;
  Timer? _timer;
  late StatusUpdate _currentStatus;
  late List<StatusMedia> _mediaItems;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.status;
    _mediaItems = _buildMediaItems(_currentStatus);
    _progressController = AnimationController(
      duration: _mediaItems[_currentIndex].duration,
      vsync: this,
    );
    _startProgress();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: GestureDetector(
        onTapDown: (details) => _handleTap(details, context),
        onLongPressStart: (_) => _pauseProgress(),
        onLongPressEnd: (_) => _resumeProgress(),
        child: Stack(
          children: [
            // Content - Full screen
            _buildContent(),
            // Header Overlay
            _buildHeaderOverlay(),
            // Caption Overlay
            _buildCaptionOverlay(),
            // Reply Area Footer
            _buildReplyArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptionOverlay() {
    if (_currentStatus.caption.isEmpty) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: 16,
      right: 16,
      bottom: 120,
      child: Text(
        _currentStatus.caption,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
          shadows: [
            Shadow(
              color: Colors.black54,
              offset: Offset(0, 1),
              blurRadius: 4,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final media = _mediaItems[_currentIndex];
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (media.type == MediaType.image)
            Image.network(
              media.url,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey[800],
                  child: const Center(
                    child: Icon(LucideIcons.imageOff, color: Colors.white, size: 50),
                  ),
                );
              },
            )
          else
            Container(
              color: Colors.black,
              child: const Center(
                child: Icon(LucideIcons.video, color: Colors.white70, size: 64),
              ),
            ),
          if (media.type == MediaType.video)
            Positioned(
              bottom: 32,
              right: 32,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Video',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 44, 16, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          children: [
            // Progress Bars
            Row(
              children: List.generate(_mediaItems.length, (index) {
                return Expanded(
                  child: Container(
                    height: 2,
                    margin: EdgeInsets.only(right: index < _mediaItems.length - 1 ? 4 : 0),
                    child: LinearProgressIndicator(
                      value: index < _currentIndex
                          ? 1.0
                          : index == _currentIndex
                              ? _progressController.value
                              : 0.0,
                      backgroundColor: Colors.white.withOpacity(0.3),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            // User Info & Close Button
            Row(
              children: [
                // User Avatar
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF29ABE2),
                    image: DecorationImage(
                      image: NetworkImage(_currentStatus.userAvatar),
                      fit: BoxFit.cover,
                      onError: (exception, stackTrace) {},
                    ),
                  ),
                  child: const Icon(LucideIcons.user, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentStatus.username,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                         _formatTimestamp(_currentStatus.timestamp),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Close Button
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: const Icon(
                      LucideIcons.x,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyArea() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _replyController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Reply...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: Colors.white),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendReply,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF29ABE2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.send,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleTap(TapDownDetails details, BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final tapPosition = details.globalPosition.dx;

    if (tapPosition > screenWidth / 2) {
      // Tapped right half - next
      _nextMedia();
    } else {
      // Tapped left half - previous
      _previousMedia();
    }
  }

  void _startProgress() {
    _progressController.forward().then((_) {
      if (!_isPaused && mounted) {
        _nextMedia();
      }
    });
  }

  void _pauseProgress() {
    setState(() => _isPaused = true);
    _progressController.stop();
  }

  void _resumeProgress() {
    setState(() => _isPaused = false);
    _progressController.forward();
  }

  void _nextMedia() {
    if (_currentIndex < _mediaItems.length - 1) {
      setState(() => _currentIndex++);
      _progressController.reset();
      _progressController.duration = _mediaItems[_currentIndex].duration;
      _startProgress();
    } else {
      _advanceToNextStatus();
    }
  }

  void _previousMedia() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _progressController.reset();
      _progressController.duration = _mediaItems[_currentIndex].duration;
      _startProgress();
    }
  }

  void _sendReply() async {
    if (_replyController.text.trim().isNotEmpty) {
      try {
        final currentUser = await AppwriteService.getCurrentUser();
        if (currentUser == null) return;

        String chatId = await AppwriteService.getChatId(currentUser.$id, widget.status.id);

        final enc = await CryptoService.encryptMessage(
          chatId: chatId,
          partnerUserId: widget.status.id,
          plaintext: _replyController.text.trim(),
        );

        await AppwriteService.createDocument(AppwriteService.messagesCollectionId, {
          'chatId': chatId,
          'senderId': currentUser.$id,
          'content': enc == null ? _replyController.text.trim() : '',
          'ciphertext': enc?['ciphertext'],
          'nonce': enc?['nonce'],
          'timestamp': DateTime.now().toIso8601String(),
          'readBy': <String>[currentUser.$id],
        });

        _replyController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reply sent!'),
            duration: Duration(seconds: 1),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send reply: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  List<StatusMedia> _buildMediaItems(StatusUpdate status) {
    final urls = status.mediaUrls;
    final items = urls.map((url) {
      final ext = url.split('.').last.toLowerCase();
      final isVideo = ['mp4', 'mov', 'webm', 'mkv'].contains(ext);
      return StatusMedia(
        id: url,
        url: url,
        type: isVideo ? MediaType.video : MediaType.image,
        duration: isVideo ? const Duration(seconds: 10) : const Duration(seconds: 5),
      );
    }).toList();
    if (items.isNotEmpty) return items;
    final fallbackUrl = status.userAvatar.isNotEmpty
        ? status.userAvatar
        : 'https://via.placeholder.com/400x600';
    return [
      StatusMedia(
        id: status.id,
        url: fallbackUrl,
        type: MediaType.image,
        duration: const Duration(seconds: 5),
      )
    ];
  }

  void _advanceToNextStatus() {
    final list = StoryManager.stories.value;
    final idx = list.indexWhere((s) => s.id == _currentStatus.id);
    if (idx >= 0 && idx + 1 < list.length) {
      final next = list[idx + 1];
      StoryManager.markViewed(next.id);
      setState(() {
        _currentStatus = next;
        _mediaItems = _buildMediaItems(next);
        _currentIndex = 0;
        _progressController.reset();
        _progressController.duration = _mediaItems[_currentIndex].duration;
      });
      _startProgress();
    } else {
      Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    _replyController.dispose();
    _timer?.cancel();
    super.dispose();
  }
}
