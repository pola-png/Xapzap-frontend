import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:appwrite/models.dart' as aw;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../models/post.dart';
import '../services/appwrite_service.dart';
import '../services/storage_service.dart';
import '../services/ad_helper.dart';
import '../widgets/voice_note_player.dart';
import '../widgets/voice_recorder.dart';
import '../widgets/taggable_text.dart';
import '../screens/hashtag_feed_screen.dart';
import '../screens/profile_screen.dart';

class CommentScreen extends StatefulWidget {
  final Post post;
  const CommentScreen({super.key, required this.post});

  @override
  State<CommentScreen> createState() => _CommentScreenState();
}

class _CommentScreenState extends State<CommentScreen> {
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  bool _loading = false;
  String? _currentUserId;
  String? _currentUserAvatarUrl;
  final Set<String> _likedCommentIds = <String>{};
  final Map<String, List<aw.Row>> _repliesByParent = <String, List<aw.Row>>{};
  final List<aw.Row> _rootComments = <aw.Row>[];
  String? _replyToCommentId;
  bool _isVoiceMode = false;

  @override
  void initState() {
    super.initState();
    _load();
    _getCurrentUser();
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

  Future<void> _getCurrentUser() async {
    final user = await AppwriteService.getCurrentUser();
    if (user == null) {
      if (mounted) {
        setState(() {
          _currentUserId = null;
          _currentUserAvatarUrl = null;
        });
      }
      return;
    }

    final prof = await AppwriteService.getProfileByUserId(user.$id);
    String? avatar = prof?.data['avatarUrl'] as String?;
    if (avatar != null && avatar.isNotEmpty && !avatar.startsWith('http')) {
      try {
        avatar = await WasabiService.getSignedUrl(avatar);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _currentUserId = user.$id;
        _currentUserAvatarUrl = avatar;
      });
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final docs = await AppwriteService.fetchComments(widget.post.id);
      if (!mounted) return;
      final rows = docs.rows;
      _rootComments.clear();
      _repliesByParent.clear();
      for (final row in rows) {
        final parentId = row.data['parentCommentId'] as String?;
        if (parentId == null || parentId.isEmpty) {
          _rootComments.add(row);
        } else {
          _repliesByParent.putIfAbsent(parentId, () => <aw.Row>[]).add(row);
        }
      }
      setState(() => _loading = false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: theme.iconTheme.color),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Comments',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surface,
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _rootComments.length,
                    itemBuilder: (context, index) {
                      // Insert ads inline: banner every 5th, native every 20th comment.
                      final widgets = <Widget>[];
                      if (index > 0 && (index + 1) % 20 == 0) {
                        widgets.add(_buildNativeAd());
                      } else if (index > 0 && (index + 1) % 5 == 0) {
                        widgets.add(_buildBannerAd());
                      }
                      widgets.add(_buildThread(_rootComments[index]));
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: widgets,
                      );
                    },
                  ),
          ),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildThread(aw.Row root) {
    final replies = _repliesByParent[root.$id] ?? const <aw.Row>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildItem(root, isReply: false),
        for (final r in replies) Padding(
          padding: const EdgeInsets.only(left: 52),
          child: _buildItem(r, isReply: true),
        ),
      ],
    );
  }

  Widget _buildBannerAd() {
    if (kIsWeb) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      height: 50,
      child: AdWidget(
        ad: BannerAd(
          size: AdSize.banner,
          adUnitId: AdHelper.banner,
          listener: BannerAdListener(
            onAdFailedToLoad: (ad, error) => ad.dispose(),
          ),
          request: const AdRequest(),
        )..load(),
      ),
    );
  }

  Widget _buildNativeAd() {
    if (kIsWeb) return const SizedBox.shrink();
    return const _InlineNativeAd(height: 320);
  }

  Widget _buildItem(aw.Row doc, {required bool isReply}) {
    final d = doc.data;
    final id = doc.$id;
    final avatarRaw = (d['userAvatar'] ?? '') as String;
    final username = d['username'] ?? 'user';
    final createdAt = d['createdAt'] ?? d['timestamp'] ?? DateTime.now().toIso8601String();
    DateTime ts;
    try {
      ts = DateTime.parse(createdAt);
    } catch (_) {
      ts = DateTime.now();
    }
    final now = DateTime.now();
    final diff = now.difference(ts);
    final timeLabel = diff.inSeconds < 60 ? 'Just now' : timeago.format(ts);
    final voiceUrl = (d['voiceUrl'] is String && (d['voiceUrl'] as String).isNotEmpty) ? d['voiceUrl'] as String : null;
    final content = (d['content'] ?? '').toString();
    final likesRaw = d['likes'];
    final repliesRaw = d['replies'];
    final likes = likesRaw is int ? likesRaw : int.tryParse('$likesRaw') ?? 0;
    final replies = repliesRaw is int ? repliesRaw : int.tryParse('$repliesRaw') ?? 0;

    final isLiked = _likedCommentIds.contains(id);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bubbleColor = isDark
        ? theme.colorScheme.primary.withOpacity(0.18)
        : const Color(0xFFF3F4F6);
    final textColor = theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: GestureDetector(
        onLongPress: () => _onCommentLongPress(doc),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<String?>(
              future: _resolveAvatar(avatarRaw),
              builder: (context, snap) {
                final url = snap.data;
                if (url == null || url.isEmpty) {
                  return CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.grey[200],
                    child: const Icon(Icons.person, color: Colors.grey),
                  );
                }
                return CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: NetworkImage(url),
                );
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              username,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: textColor,
                              ),
                            ),
                          const SizedBox(width: 8),
                          Text(
                            timeLabel,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (voiceUrl != null)
                          VoiceNotePlayer(url: voiceUrl)
                        else
                          TaggableExpandableText(
                            text: content,
                            style: TextStyle(
                              fontSize: 20,
                              color: textColor,
                              height: 1.5,
                            ),
                            onMentionTap: (usernameToken) async {
                              final handle = usernameToken.replaceAll('@', '').trim();
                              if (handle.isEmpty) return;
                              final prof =
                                  await AppwriteService.getProfileByUsername(handle);
                              if (!mounted) return;
                              if (prof == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('User @$handle not found')),
                                );
                                return;
                              }
                              final data = prof.data;
                              final userId = data['userId'] as String? ?? prof.$id;
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ProfileScreen(userId: userId),
                                ),
                              );
                            },
                            onHashtagTap: (tagToken) {
                              final clean = tagToken.replaceAll('#', '').trim();
                              if (clean.isEmpty) return;
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => HashtagFeedScreen(tag: clean),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (_currentUserId == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Sign in to like comments.')),
                            );
                            return;
                          }
                          setState(() {
                            final currentLikesRaw = d['likes'];
                            final currentLikes = currentLikesRaw is int
                                ? currentLikesRaw
                                : int.tryParse('$currentLikesRaw') ?? 0;
                            if (isLiked) {
                              _likedCommentIds.remove(id);
                              d['likes'] = (currentLikes - 1).clamp(0, 1 << 31);
                            } else {
                              _likedCommentIds.add(id);
                              d['likes'] = (currentLikes + 1).clamp(0, 1 << 31);
                            }
                          });
                          // Persist like state (optimistic, fire and forget)
                          if (isLiked) {
                            AppwriteService.unlikeComment(id);
                          } else {
                            AppwriteService.likeComment(id);
                          }
                        },
                        child: Text(
                          likes > 0 ? 'Like $likes' : 'Like',
                          style: TextStyle(
                            fontSize: 16,
                            color: isLiked ? const Color(0xFF1DA1F2) : Colors.grey[600],
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () {
                        _commentController.text = '@$username ';
                        _commentController.selection = TextSelection.fromPosition(
                          TextPosition(offset: _commentController.text.length),
                        );
                        _replyToCommentId = id;
                        _inputFocusNode.requestFocus();
                      },
                      child: Text(
                        replies > 0 ? 'Reply $replies' : 'Reply',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final inputFillColor = isDark ? const Color(0xFF111827) : Colors.grey[100];
    final textColor = theme.textTheme.bodyMedium?.color ?? Colors.black;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.background,
      child: SafeArea(
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
                      focusNode: _inputFocusNode,
                      decoration: InputDecoration(
                        hintText: 'Add a comment...',
                        hintStyle: TextStyle(color: textColor.withOpacity(0.6)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                        filled: true,
                        fillColor: inputFillColor,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      style: TextStyle(color: textColor, fontSize: 16),
                      onSubmitted: _submit,
                    ),
            ),
            if (!_isVoiceMode) ...[
              IconButton(
                icon: const Icon(LucideIcons.mic, color: Color(0xFF1DA1F2)),
                onPressed: () {
                  if (_currentUserId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Sign in to record voice comments.')),
                    );
                    return;
                  }
                  setState(() => _isVoiceMode = true);
                },
              ),
              IconButton(
                icon: const Icon(LucideIcons.send, color: Color(0xFF1DA1F2)),
                onPressed: () => _submit(_commentController.text),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _submit(String text) async {
    final content = text.trim();
    if (content.isEmpty) return;
    try {
      aw.Row doc;
      final replyingTo = _replyToCommentId;
      if (replyingTo != null) {
        doc = await AppwriteService.createReplyComment(widget.post.id, replyingTo, content);
        await AppwriteService.incrementCommentReplies(replyingTo, 1);
      } else {
        doc = await AppwriteService.createComment(widget.post.id, content);
      }
      if (!mounted) return;
      setState(() {
        if (replyingTo != null) {
          _repliesByParent.putIfAbsent(replyingTo, () => <aw.Row>[]).insert(0, doc);
          // bump local replies count on parent
          final parentIndex = _rootComments.indexWhere((r) => r.$id == replyingTo);
          if (parentIndex != -1) {
            final pd = _rootComments[parentIndex].data;
            final raw = pd['replies'];
            final current = raw is int ? raw : int.tryParse('$raw') ?? 0;
            pd['replies'] = (current + 1).clamp(0, 1 << 31);
          }
        } else {
          _rootComments.insert(0, doc);
        }
        _replyToCommentId = null;
        _commentController.clear();
      });
      await AppwriteService.incrementPostComments(widget.post.id, 1);
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to comment: $e')));
    }
  }

  Future<void> _handleVoiceRecorded(String? path) async {
    setState(() => _isVoiceMode = false);
    if (path == null || _currentUserId == null) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final voiceUrl = await WasabiService.uploadVoiceComment(path, _currentUserId!);
      if (voiceUrl == null) return;

      final doc = await AppwriteService.createVoiceComment(widget.post.id, voiceUrl);
      await AppwriteService.incrementPostComments(widget.post.id, 1);

      if (!mounted) return;
      setState(() {
        _rootComments.insert(0, doc);
      });

      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Voice comment posted!')));
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Failed to post voice comment.')));
    }
  }

  Future<void> _onCommentLongPress(aw.Row doc) async {
    final d = doc.data;
    final ownerId = d['userId'] as String?;
    if (_currentUserId == null || ownerId != _currentUserId) {
      return;
    }
    final voiceUrl = (d['voiceUrl'] is String && (d['voiceUrl'] as String).isNotEmpty)
        ? d['voiceUrl'] as String
        : null;

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (voiceUrl == null)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit comment'),
                onTap: () => Navigator.of(ctx).pop('edit'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete comment'),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );

    if (action == 'edit' && voiceUrl == null) {
      final controller = TextEditingController(text: (d['content'] ?? '').toString());
      final newText = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Edit comment'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: null,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (newText == null || newText.isEmpty) return;
      try {
        final updated = await AppwriteService.updateRow(
          AppwriteService.commentsCollectionId,
          doc.$id,
          {'content': newText},
        );
        if (!mounted) return;
        setState(() {
          final parentId = d['parentCommentId'] as String?;
          if (parentId != null && parentId.isNotEmpty) {
            final list = _repliesByParent[parentId];
            if (list != null) {
              final idx = list.indexWhere((r) => r.$id == doc.$id);
              if (idx != -1) list[idx] = updated;
            }
          } else {
            final idx = _rootComments.indexWhere((r) => r.$id == doc.$id);
            if (idx != -1) _rootComments[idx] = updated;
          }
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update comment: $e')),
        );
      }
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete comment?'),
          content: const Text('This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final parentId = d['parentCommentId'] as String?;
      try {
        await AppwriteService.deleteComment(doc.$id);
        await AppwriteService.incrementPostComments(widget.post.id, -1);
        if (parentId != null && parentId.isNotEmpty) {
          await AppwriteService.incrementCommentReplies(parentId, -1);
        }
        if (!mounted) return;
        setState(() {
          if (parentId != null && parentId.isNotEmpty) {
            final list = _repliesByParent[parentId];
            list?.removeWhere((r) => r.$id == doc.$id);
            // decrement local replies count on parent
            final parentIndex = _rootComments.indexWhere((r) => r.$id == parentId);
            if (parentIndex != -1) {
              final pd = _rootComments[parentIndex].data;
              final raw = pd['replies'];
              final current = raw is int ? raw : int.tryParse('$raw') ?? 0;
              pd['replies'] = (current - 1).clamp(0, 1 << 31);
            }
          } else {
            _rootComments.removeWhere((r) => r.$id == doc.$id);
            _repliesByParent.remove(doc.$id);
          }
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete comment: $e')),
        );
      }
    }
  }
}

class _InlineNativeAd extends StatefulWidget {
  final double height;
  const _InlineNativeAd({required this.height});

  @override
  State<_InlineNativeAd> createState() => _InlineNativeAdState();
}

class _InlineNativeAdState extends State<_InlineNativeAd> {
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
