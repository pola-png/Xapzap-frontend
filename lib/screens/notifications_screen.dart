import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/status.dart';
import '../services/story_manager.dart';
import 'status_viewer_screen.dart';
import 'story_publish_screen.dart';
import '../models/app_notification.dart';
import '../services/appwrite_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    StoryManager.init();
    StoryManager.loadFromServer();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Updates'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Status'),
              Tab(text: 'Notifications'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildStatusTab(),
            _NotificationsList(isDark: isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTab() {
    return ValueListenableBuilder<List<StatusUpdate>>(
      valueListenable: StoryManager.stories,
      builder: (context, statuses, _) {
        final others = statuses.where((s) => s.id != 'me').toList();
        final unviewed = others.where((s) => !s.isViewed).toList();
        final viewed = others.where((s) => s.isViewed).toList();
        final myStatus = statuses.firstWhere(
          (s) => s.id == 'me',
          orElse: () => statuses.isNotEmpty ? statuses.first : StoryManager.stories.value.first,
        );
        return RefreshIndicator(
          onRefresh: () => StoryManager.loadFromServer(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              ListTile(
                onTap: _showStoryOptions,
                leading: Stack(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.grey.shade300,
                      backgroundImage: myStatus.userAvatar.isNotEmpty ? NetworkImage(myStatus.userAvatar) : null,
                      child: myStatus.userAvatar.isEmpty ? const Icon(Icons.person, color: Colors.white) : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF00A884),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.add, size: 12, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                title: const Text('My status', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Tap to add status update'),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Recent updates',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF6B7280)),
                ),
              ),
              if (unviewed.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No new stories from people you follow yet.')),
                ),
              ...unviewed.map(_buildStatusTile),
              if (viewed.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Viewed updates',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF6B7280)),
                  ),
                ),
              ...viewed.map((status) => _buildStatusTile(status, viewed: true)),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showStoryOptions() async {
    await showModalBottomSheet(
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
                title: const Text('Choose photo'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickStory(ImageSource.gallery, video: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library),
                title: const Text('Choose video'),
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
      final file = video
          ? await _picker.pickVideo(source: source, maxDuration: const Duration(seconds: 60))
          : await _picker.pickImage(source: source);
      if (file == null || !mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StoryPublishScreen(media: file)),
      );
    } catch (_) {}
  }

  void _openStatus(StatusUpdate status) {
    status.isViewed = true;
    StoryManager.markViewed(status.id);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StatusViewerScreen(status: status)),
    );
  }

  Widget _buildStatusTile(StatusUpdate status, {bool viewed = false}) {
    return ListTile(
      onTap: () => _openStatus(status),
      leading: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: viewed ? Colors.black : const Color(0xFF29ABE2),
            width: 2,
          ),
        ),
        child: CircleAvatar(
          radius: 24,
          backgroundImage: status.userAvatar.isNotEmpty ? NetworkImage(status.userAvatar) : null,
          backgroundColor: Colors.grey.shade200,
          child: status.userAvatar.isEmpty ? const Icon(Icons.person, color: Colors.white) : null,
        ),
      ),
      title: Text(status.username, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(_formatTimestamp(status.timestamp)),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inDays > 0) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
    }
    return 'Just now';
  }
}

class _NotificationsList extends StatefulWidget {
  final bool isDark;

  const _NotificationsList({required this.isDark});

  @override
  State<_NotificationsList> createState() => _NotificationsListState();
}

class _NotificationsListState extends State<_NotificationsList> {
  List<AppNotification> _notifications = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final user = await AppwriteService.getCurrentUser();
    if (!mounted) return;
    if (user == null) {
      setState(() {
        _notifications = const [];
        _loading = false;
      });
      return;
    }
    final items = await AppwriteService.fetchNotifications(user.$id);
    if (!mounted) return;
    setState(() {
      _notifications = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final subtitleColor =
        widget.isDark ? const Color(0xFF8696A0) : const Color(0xFF6B7280);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_notifications.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: Text('No notifications yet')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _notifications.length,
        separatorBuilder: (context, index) => Divider(
          height: 0,
          indent: 72,
          color: widget.isDark ? const Color(0xFF202C33) : const Color(0xFFE5E7EB),
        ),
        itemBuilder: (context, index) {
          final notification = _notifications[index];
          return ListTile(
            leading: CircleAvatar(
              radius: 24,
              backgroundImage: notification.actorAvatar != null &&
                      notification.actorAvatar!.isNotEmpty
                  ? NetworkImage(notification.actorAvatar!)
                  : null,
              child: (notification.actorAvatar == null ||
                      notification.actorAvatar!.isEmpty)
                  ? const Icon(Icons.notifications)
                  : null,
            ),
            title: Text(notification.title),
            subtitle: Text(
              notification.body.isNotEmpty
                  ? '${notification.body}\n${_formatTimestamp(notification.timestamp)}'
                  : _formatTimestamp(notification.timestamp),
              style: TextStyle(color: subtitleColor),
            ),
            isThreeLine: notification.body.isNotEmpty,
          );
        },
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    }
    return 'Just now';
  }
}
