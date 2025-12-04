import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as aw;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/post.dart';
import '../services/appwrite_service.dart';
import '../services/storage_service.dart';
import '../widgets/post_card.dart';
import '../widgets/voice_recorder.dart';
import '../widgets/voice_note_player.dart';
import '../utils/news_seo.dart';

class PostDetailScreen extends StatefulWidget {
  final Post post;
  final List<String>? mediaUrls;
  final String? authorId;
  final bool isGuest;
  final VoidCallback? onGuestAction;

  const PostDetailScreen({
    super.key,
    required this.post,
    this.mediaUrls,
    this.authorId,
    this.isGuest = false,
    this.onGuestAction,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _commentFocusNode = FocusNode();
  bool _loadingComments = false;
  String? _currentUserId;
  final Set<String> _likedCommentIds = <String>{};
  final Map<String, List<aw.Row>> _repliesByParent = <String, List<aw.Row>>{};
  final List<aw.Row> _rootComments = <aw.Row>[];
  String? _replyToCommentId;
  bool _isVoiceMode = false;
  String? _currentUserAvatarUrl;
  NewsSeo? _newsSeo;

  @override
  void initState() {
    super.initState();
    _loadComments();
    _getCurrentUser();
    _maybeInitNewsSeo();
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

  Future<void> _loadComments() async {
    setState(() => _loadingComments = true);
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
      setState(() => _loadingComments = false);
    } finally {
      if (mounted) setState(() => _loadingComments = false);
    }
  }

  void _maybeInitNewsSeo() {
    final kind = widget.post.kind?.toLowerCase() ?? '';
    final isNews = kind.contains('news') || kind.contains('blog');
    if (!isNews) return;
    final seo = buildNewsSeo(widget.post.title ?? '', widget.post.content);
    setState(() => _newsSeo = seo);
    // Best-effort: persist SEO fields back to Appwrite for future use.
    AppwriteService.updatePostSeo(
      widget.post.id,
      seoTitle: seo.seoTitle,
      seoDescription: seo.seoDescription,
      seoSlug: seo.seoSlug,
      seoKeywords: seo.seoKeywords,
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: Text(
          'Post',
          style: TextStyle(color: theme.colorScheme.onSurface),
        ),
        iconTheme: IconThemeData(color: theme.iconTheme.color),
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.zero,
              itemCount: 1 + (_newsSeo != null ? 1 : 0) + (_loadingComments ? 1 : _rootComments.length),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: PostCard(
                      post: widget.post,
                      isGuest: widget.isGuest,
                      onGuestAction: widget.onGuestAction,
                      mediaUrls: widget.mediaUrls,
                      authorId: widget.authorId,
                      onOpenPost: null,
                      isDetail: true,
                    ),
                  );
                }
                if (index == 1 && _newsSeo != null) {
                  final seo = _newsSeo!;
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    margin: const EdgeInsets.only(bottom: 8),
                    color: theme.colorScheme.surface,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SEO summary',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          seo.seoTitle,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          seo.seoDescription,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (seo.seoKeywords.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: seo.seoKeywords
                                .map(
                                  (k) => Chip(
                                    label: Text(k),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity:
                                        VisualDensity.compact,
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  );
                }
                final offset = 1 + (_newsSeo != null ? 1 : 0);
                final commentIndex = index - offset;
                if (_loadingComments) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final doc = _rootComments[index - 1];
                return _buildCommentThread(doc);
              },
            ),
          ),
          _buildCommentInput(),
        ],
      ),
    );
  }

  Widget _buildCommentThread(aw.Row root) {
    final replies = _repliesByParent[root.$id] ?? const <aw.Row>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCommentItem(root),
        for (final r in replies)
          Padding(
            padding: const EdgeInsets.only(left: 52),
            child: _buildCommentItem(r, isReply: true),
          ),
      ],
    );
  }

  Widget _buildCommentItem(aw.Row doc, {bool isReply = false}) {
    final d = doc.data;
    final id = doc.$id;
    final avatarRaw = (d['userAvatar'] as String?) ?? '';
    final username = d['username'] as String? ?? 'user';
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
    final likesRaw = d['likes'];
    final repliesRaw = d['replies'];
    final likes = likesRaw is int ? likesRaw : int.tryParse('$likesRaw') ?? 0;
    final replies = repliesRaw is int ? repliesRaw : int.tryParse('$repliesRaw') ?? 0;
    final voiceUrl = (d['voiceUrl'] is String && (d['voiceUrl'] as String).isNotEmpty)
        ? d['voiceUrl'] as String
        : null;
    final content = (d['content'] ?? '').toString();
    final isLiked = _likedCommentIds.contains(id);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bubbleColor = isDark
        ? theme.colorScheme.primary.withOpacity(0.18)
        : const Color(0xFFF3F4F6);
    final textColor = theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
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
                          Text(
                            content,
                            style: TextStyle(
                              fontSize: 20,
                              color: textColor,
                              height: 1.5,
                            ),
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
                          _commentFocusNode.requestFocus();
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
                      style: TextStyle(color: textColor),
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
                icon: const Icon(Icons.send, color: Color(0xFF1DA1F2)),
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
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to comment: $e')),
      );
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

  Future<void> _handleVoiceRecorded(String? path) async {
    setState(() => _isVoiceMode = false);
    if (path == null) return;
    if (_currentUserId == null || widget.isGuest) {
      widget.onGuestAction?.call();
      return;
    }
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
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Failed to post voice comment.')));
    }
  }
}
