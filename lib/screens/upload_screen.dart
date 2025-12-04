import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../models/upload_type.dart';
import '../services/pending_upload_service.dart';
import '../services/appwrite_service.dart';

class UploadScreen extends StatefulWidget {
  final UploadType type;
  const UploadScreen({super.key, required this.type});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final List<XFile> _selectedMedia = [];
  final ImagePicker _picker = ImagePicker();
  final List<Color> _textBgOptions = const [
    Color(0xFF0EA5E9), // sky
    Color(0xFF10B981), // green
    Color(0xFFF59E0B), // amber
    Color(0xFFE11D48), // rose
    Color(0xFF6366F1), // indigo
    Color(0xFF111827), // dark
  ];
  Color? _selectedTextBg;
  bool _isPosting = false;
  XFile? _selectedVideo;
  XFile? _selectedThumbnail;
  VideoPlayerController? _videoController;
  Future<void>? _videoInit;
  bool _isVideoPlaying = false;
  bool _isAdmin = false;
  Duration _videoDuration = Duration.zero;
  final Set<String> _bannedKeywords = const {
    'sex',
    'nude',
    'nudity',
    'porn',
    'xxx',
    'nsfw',
    'explicit',
  };

  bool _canUseBg() => _selectedMedia.isEmpty && _selectedTextBg != null && _textController.text.length <= 50;

  bool _containsBannedText() {
    final combined = '${_titleController.text} ${_textController.text}'.toLowerCase();
    for (final word in _bannedKeywords) {
      if (combined.contains(word)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = switch (widget.type) {
      UploadType.standard => 'New Post',
      UploadType.video => 'New Video',
      UploadType.reel => 'New Reel',
      UploadType.news => 'News / Blog',
    };

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Container(
        constraints: const BoxConstraints(maxWidth: 768),
        child: Column(
          children: [
            _buildHeader(title),
            Expanded(child: _buildContentArea()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadAdminStatus();
  }

  Future<void> _loadAdminStatus() async {
    final isAdmin = await AppwriteService.isCurrentUserAdmin();
    if (mounted) {
      setState(() {
        _isAdmin = isAdmin;
      });
    } else {
      _isAdmin = isAdmin;
    }
  }

  Widget _buildHeader(String title) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 44, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.96),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Icon(LucideIcons.arrowLeft, size: 24, color: theme.colorScheme.onSurface),
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF1DA1F2)),
          ),
          const SizedBox(width: 24),
        ],
      ),
    );
  }

  Widget _buildContentArea() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = theme.colorScheme.surface;
    final fieldFillStrong = isDark ? const Color(0xFF111827) : const Color(0xFFF3F4F6);
    final fieldFillSoft = isDark ? const Color(0xFF020617) : const Color(0xFFF9FAFB);
    final textColor = theme.textTheme.bodyLarge?.color ?? (isDark ? Colors.white : Colors.black87);

    if (widget.type == UploadType.video || widget.type == UploadType.reel) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildVideoPreview(),
                  const SizedBox(height: 12),
                  if (widget.type == UploadType.video)
                    TextField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        hintText: 'Title of the movie',
                        hintStyle: TextStyle(fontSize: 18, color: theme.hintColor),
                        filled: true,
                        fillColor: fieldFillStrong,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      style: TextStyle(fontSize: 18, color: textColor, fontWeight: FontWeight.w600),
                    ),
                  if (widget.type == UploadType.video) const SizedBox(height: 12),
                  TextField(
                    controller: _textController,
                    maxLines: 4,
                    minLines: 3,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: InputDecoration(
                      hintText: widget.type == UploadType.reel
                          ? 'Add a caption for your reel (you can include #tags)'
                          : 'Say something about your video (add #tags, mentions...)',
                      hintStyle: TextStyle(fontSize: 16, color: theme.hintColor),
                      filled: true,
                      fillColor: fieldFillSoft,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    style: TextStyle(fontSize: 16, color: textColor),
                    onChanged: (value) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  _buildVideoSelectors(),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildNudityWarning(),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
          child: Column(
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: _canUseBg() ? _selectedTextBg : null,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: _canUseBg() ? const EdgeInsets.all(8) : EdgeInsets.zero,
                  child: TextField(
                    controller: _textController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    textAlign: _canUseBg() ? TextAlign.center : TextAlign.start,
                    decoration: InputDecoration.collapsed(
                      hintText: widget.type == UploadType.news
                          ? 'Write your news or blog...'
                          : "What's on your mind?",
                      hintStyle: TextStyle(fontSize: 18, color: theme.hintColor),
                    ),
                    style: TextStyle(
                      fontSize: 18,
                      color: textColor,
                      fontWeight: _textController.text.length < 40
                          ? FontWeight.w800
                          : (_textController.text.length < 120 ? FontWeight.w700 : FontWeight.w600),
                    ),
                    onChanged: (value) {
                      if (value.length > 50 && _selectedTextBg != null) {
                        _selectedTextBg = null;
                      }
                      setState(() {});
                    },
                  ),
                ),
              ),
              if (_selectedMedia.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ..._textBgOptions.map(
                        (c) => GestureDetector(
                          onTap: () => setState(() => _selectedTextBg = c),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _selectedTextBg == c ? Colors.white : Colors.white54,
                                width: _selectedTextBg == c ? 3 : 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _selectedTextBg = null),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: theme.dividerColor),
                          ),
                          child: Text(
                            'No color',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_selectedMedia.isNotEmpty) _buildMediaPreview(),
              const SizedBox(height: 12),
              _buildAddMediaButton(),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      _buildNudityWarning(),
    ],
  ),
);
  }

  Widget _buildNudityWarning() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseRed = Colors.red;
    final bg = isDark ? baseRed.withOpacity(0.16) : baseRed.withOpacity(0.06);
    final border = baseRed.withOpacity(0.6);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 0.7),
      ),
      child: const Row(
        children: [
          Icon(LucideIcons.alertTriangle, color: Colors.red, size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Nudity and explicit content are strictly forbidden. Accounts violating this policy will be terminated.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddMediaButton() {
    return GestureDetector(
      onTap: () {
        if (widget.type == UploadType.standard || widget.type == UploadType.news) {
          _pickFromGallery();
        }
      },
      child: Row(
        children: [
          Icon(
            widget.type == UploadType.news ? LucideIcons.fileEdit : LucideIcons.image,
            size: 20,
            color: const Color(0xFF1DA1F2),
          ),
          const SizedBox(width: 8),
          Text(
            widget.type == UploadType.news ? 'Add cover image (optional)' : 'Add Photos/Videos',
            style: const TextStyle(fontSize: 16, color: Color(0xFF1DA1F2), fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPreview() {
    return Container(
      height: 120,
      margin: const EdgeInsets.only(top: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedMedia.length,
        itemBuilder: (context, index) {
          final media = _selectedMedia[index];
          return Container(
            width: 120,
            margin: const EdgeInsets.only(right: 8),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(media.path),
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => _removeMedia(index),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(LucideIcons.x, color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFooter() {
    final hasStandardContent =
        _textController.text.trim().isNotEmpty || _selectedMedia.isNotEmpty;
    final hasVideoContent = widget.type == UploadType.video
        ? _titleController.text.trim().isNotEmpty &&
            _textController.text.trim().isNotEmpty &&
            _selectedVideo != null
        : true;
    final hasContent = hasStandardContent && hasVideoContent;

    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      color: theme.colorScheme.surface,
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: hasContent && !_isPosting ? _createPost : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: hasContent ? const Color(0xFF1DA1F2) : theme.disabledColor.withOpacity(0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            elevation: hasContent ? 4 : 0,
          ),
          child: _isPosting
              ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white))
              : const Text('Post', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      ),
    );
  }

  Future<void> _pickFromGallery() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        _selectedMedia.addAll(images);
        _selectedTextBg = null;
      });
    }
  }

  Widget _buildVideoSelectors() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(LucideIcons.video, color: Color(0xFF1DA1F2)),
          title: Text(
            _selectedVideo != null ? 'Change video' : 'Select video',
            style: const TextStyle(fontSize: 16),
          ),
          subtitle: _selectedVideo != null
              ? Text(
                  _selectedVideo!.name,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                )
              : const Text('Horizontal for Videos, vertical for Reels',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
          onTap: () => _pickVideo(),
        ),
        if (widget.type == UploadType.video) ...[
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.image, color: Color(0xFF1DA1F2)),
            title: Text(
              _selectedThumbnail != null ? 'Change thumbnail' : 'Add thumbnail',
              style: const TextStyle(fontSize: 16),
            ),
            subtitle: _selectedThumbnail != null
                ? Text(
                    _selectedThumbnail!.name,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  )
                : const Text('Optional cover image for the movie',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
            onTap: () => _pickThumbnail(),
          ),
        ],
      ],
    );
  }

  Widget _buildVideoPreview() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    if (_selectedVideo == null) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant.withOpacity(isDark ? 0.2 : 0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            'Select a video to preview',
            style: TextStyle(color: Color(0xFF6B7280)),
          ),
        ),
      );
    }
    if (_videoInit == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return FutureBuilder<void>(
      future: _videoInit,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done || _videoController == null) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final aspect = _videoController!.value.aspectRatio == 0
            ? 16 / 9
            : _videoController!.value.aspectRatio;
        return GestureDetector(
          onTap: () async {
            if (_videoController == null) return;
            if (_videoController!.value.isPlaying) {
              await _videoController!.pause();
              setState(() => _isVideoPlaying = false);
            } else {
              await _videoController!.seekTo(Duration.zero);
              await _videoController!.play();
              setState(() => _isVideoPlaying = true);
            }
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: aspect,
                child: VideoPlayer(_videoController!),
              ),
              if (!_isVideoPlaying)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Icon(Icons.play_arrow, color: Colors.white, size: 36),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickVideo() async {
    final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video != null) {
      final isVertical = await _isVerticalVideo(video);
      if (widget.type == UploadType.video && isVertical) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Horizontal videos only for Videos. Use Reels for vertical videos.')),
          );
        }
        return;
      }
      if (widget.type == UploadType.reel && !isVertical) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vertical videos only for Reels. Use Videos for horizontal videos.')),
          );
        }
        return;
      }
      final accepted = await _maybeHandleLongVideo(video);
      if (accepted) {
        _setPreviewVideo(video);
      }
    }
  }

  Future<void> _pickThumbnail() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedThumbnail = image;
      });
    }
  }

  void _removeMedia(int index) {
    setState(() {
      _selectedMedia.removeAt(index);
    });
  }

  Future<bool> _maybeHandleLongVideo(XFile video) async {
    final controller = VideoPlayerController.file(File(video.path));
    try {
      await controller.initialize();
      final duration = controller.value.duration;
      await controller.dispose();
      if (duration.inSeconds <= 30) {
        return true;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Uploads are limited to 30 seconds. Please choose a shorter clip.')),
        );
      }
      return false;
    } catch (_) {
      await controller.dispose();
      return false;
    }
  }

  Future<bool> _isVerticalVideo(XFile file) async {
    final controller = VideoPlayerController.file(File(file.path));
    try {
      await controller.initialize();
      final size = controller.value.size;
      await controller.dispose();
      if (size.width == 0 || size.height == 0) return false;
      return size.height > size.width;
    } catch (_) {
      await controller.dispose();
      return false;
    }
  }

  void _setPreviewVideo(XFile video) {
    _videoController?.dispose();
    _videoController = VideoPlayerController.file(File(video.path));
    _videoInit = _videoController!.initialize().then((_) {
      final duration = _videoController?.value.duration ?? Duration.zero;
      setState(() {
        _isVideoPlaying = false;
        _selectedVideo = video;
        _videoDuration = duration;
      });
    });
  }

  Future<void> _createPost() async {
    if (_isPosting) return;
    if (_containsBannedText()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Posting blocked: nudity/explicit content not allowed.')),
      );
      return;
    }
    setState(() => _isPosting = true);
    try {
      String? effectiveVideo = _selectedVideo?.path;
      final cleanup = <String>[];

      if (_selectedVideo != null) {
        final durationSecs = _videoDuration.inSeconds;
        if (!_isAdmin && durationSecs > 30) {
          if (mounted) {
            setState(() => _isPosting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Only admins can post videos longer than 30 seconds.')),
            );
          }
          return;
        }
      }

      final request = PostUploadRequest(
        type: widget.type,
        content: _textController.text.trim(),
        title: _titleController.text.trim(),
        mediaPaths: _selectedMedia.map((m) => m.path).toList(),
        videoPath: effectiveVideo,
        thumbnailPath: _selectedThumbnail?.path,
        cleanupPaths: cleanup,
        textBgColor: _canUseBg() ? _selectedTextBg?.value : null,
      );
      PendingUploadService.enqueuePostUpload(request);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Post is uploading-track it in the feed banner!'),
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _titleController.dispose();
    _videoController?.dispose();
    super.dispose();
  }
}
