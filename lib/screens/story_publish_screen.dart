import 'dart:io';

import 'package:appwrite/appwrite.dart' show ID;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../models/status.dart';
import '../services/appwrite_service.dart';
import '../services/story_manager.dart';
import '../services/storage_service.dart';

class StoryPublishScreen extends StatefulWidget {
  final XFile media;

  const StoryPublishScreen({super.key, required this.media});

  @override
  State<StoryPublishScreen> createState() => _StoryPublishScreenState();
}

class _StoryPublishScreenState extends State<StoryPublishScreen> {
  final TextEditingController _captionController = TextEditingController();
  bool _isUploading = false;
  VideoPlayerController? _videoController;
  double _trimStart = 0.0;
  static const double _maxClipLength = 10.0;
  bool get _isVideo =>
      widget.media.path.toLowerCase().endsWith('.mp4') ||
      widget.media.path.toLowerCase().endsWith('.mov') ||
      widget.media.path.toLowerCase().endsWith('mkv') ||
      widget.media.path.toLowerCase().endsWith('.webm');
  double get _videoDuration =>
      _videoController?.value.duration.inSeconds.toDouble() ?? 0.0;
  double get _sliderMax =>
      (_videoDuration - _maxClipLength).clamp(0.0, double.infinity);
  double get _fileSizeMb =>
      File(widget.media.path).lengthSync() / (1024 * 1024);
  String get _fileSizeLabel => '${_fileSizeMb.toStringAsFixed(1)} MB';

  @override
  void initState() {
    super.initState();
    if (_isVideo) {
      _videoController = VideoPlayerController.file(File(widget.media.path))
        ..initialize().then((_) {
          setState(() {});
          _videoController?.setLooping(true);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final List<IconData> topIcons = [
      Icons.close,
      Icons.music_note,
      Icons.switch_camera,
      Icons.crop_square,
      Icons.text_fields,
      Icons.edit,
    ];

    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildMediaPreview()),
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: topIcons
                    .map(
                      (icon) => CircleAvatar(
                        radius: 20,
              backgroundColor: isDark ? Colors.black54 : Colors.black.withOpacity(0.15),
                        child: Icon(icon, color: Colors.white, size: 20),
                      ),
                    )
                    .toList(),
              ),
            ),
            if (_isVideo && _videoController?.value.isInitialized == true)
              Positioned(
                top: 80,
                left: 24,
                right: 24,
                child: _buildTrimSlider(theme),
              ),
            Positioned(
              bottom: 180,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Swipe up for filters',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black,
                      Colors.black.withOpacity(0.0),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.photo, color: Colors.white54),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _captionController,
                            style: const TextStyle(color: Colors.white),
                            maxLines: null,
                            decoration: InputDecoration(
                              hintText: 'Add a caption...',
                              hintStyle:
                                  const TextStyle(color: Colors.white60),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _isUploading ? null : _postStory,
                          child: CircleAvatar(
                            radius: 26,
                            backgroundColor: Colors.green,
                            child: Icon(
                              _isUploading
                                  ? Icons.hourglass_top
                                  : Icons.send,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_isVideo)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${_formatDuration(_maxClipLength)} • $_fileSizeLabel',
                          style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white60,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _postStory() async {
    if (_isUploading) return;
    setState(() => _isUploading = true);
    try {
      final me = await AppwriteService.getCurrentUser();
      if (me == null) return;
      final profile = await AppwriteService.getProfileByUserId(me.$id);
      final avatar = profile?.data['avatarUrl'] as String? ?? '';
      final displayNameCandidate =
          (profile?.data['displayName'] as String?)?.trim();
      final usernameCandidate =
          (profile?.data['username'] as String?)?.trim();
      final fallbackName = me.name.isNotEmpty ? me.name : 'You';
      late final String displayName;
      if (displayNameCandidate?.isNotEmpty == true) {
        displayName = displayNameCandidate!;
      } else if (usernameCandidate?.isNotEmpty == true) {
        displayName = usernameCandidate!;
      } else {
        displayName = fallbackName;
      }

      final ext = widget.media.name.split('.').last;
      final path =
          'stories/${me.$id}/story_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final storedPath =
          await WasabiService.uploadFileAtPath(File(widget.media.path), path);
      final url = await WasabiService.getSignedUrl(storedPath);
      final statusId = ID.unique();

      await StoryManager.addStatus(StatusUpdate(
        id: statusId,
        username: displayName,
        userAvatar: avatar,
        timestamp: DateTime.now(),
        isViewed: false,
        mediaCount: 1,
        mediaUrls: [url],
        caption: _captionController.text.trim(),
      ));
      await AppwriteService.createStatus(
        statusId,
        me.$id,
        storedPath,
        DateTime.now(),
        caption: _captionController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Story upload failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Widget _buildMediaPreview() {
    if (_isVideo &&
        _videoController != null &&
        _videoController!.value.isInitialized) {
      final maxHeight = MediaQuery.of(context).size.height * 0.72;
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio,
            child: VideoPlayer(_videoController!),
          ),
        ),
      );
    }
    return Image.file(
      File(widget.media.path),
      fit: BoxFit.cover,
    );
  }

  Widget _buildTrimSlider(ThemeData theme) {
    final sliderMax = _sliderMax;
    final sliderValue = _trimStart.clamp(0.0, sliderMax);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Slider(
            min: 0,
            max: sliderMax,
            value: sliderValue,
            activeColor: Colors.white,
            inactiveColor: Colors.white24,
            onChanged: (value) {
              setState(() => _trimStart = value);
              _videoController?.seekTo(Duration(seconds: value.toInt()));
            },
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${_trimStart.toStringAsFixed(1)}s',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            Text(
              'Posting ${_maxClipLength.toInt()}s clip',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDuration(double seconds) {
    final dur = Duration(seconds: seconds.toInt());
    final minutes = dur.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = dur.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _captionController.dispose();
    super.dispose();
  }
}
