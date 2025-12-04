import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as aw;
import 'package:appwrite/appwrite.dart' show Query;
import '../services/appwrite_service.dart';
import '../services/storage_service.dart';

class LiveScreen extends StatefulWidget {
  final bool isGuest;
  const LiveScreen({super.key, this.isGuest = false});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  final _titleController = TextEditingController();
  bool _isStarting = false;
  List<aw.Row> _liveSessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLiveSessions();
  }

  Future<void> _loadLiveSessions() async {
    setState(() => _loading = true);
    try {
      final res = await AppwriteService.getDocuments(
        AppwriteService.postsCollectionId,
        queries: [
          Query.equal('postType', 'live'),
          Query.orderDesc('createdAt'),
          Query.limit(50),
        ],
      );
      if (mounted) {
        setState(() {
          _liveSessions = res.rows;
        });
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startLive() async {
    if (widget.isGuest) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please sign in to go live.')));
      return;
    }
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a live title')));
      return;
    }
    setState(() => _isStarting = true);
    try {
      final user = await AppwriteService.getCurrentUser();
      if (user == null) throw Exception('Login required');
      String? avatarUrl;
      try {
        final prof = await AppwriteService.getProfileByUserId(user.$id);
        avatarUrl = prof?.data['avatarUrl'] as String?;
        if (avatarUrl != null && avatarUrl.isNotEmpty && !avatarUrl.startsWith('http')) {
          avatarUrl = await WasabiService.getSignedUrl(avatarUrl);
        }
      } catch (_) {}

      final data = <String, dynamic>{
        'userId': user.$id,
        'username': user.name,
        if (avatarUrl != null && avatarUrl.isNotEmpty) 'userAvatar': avatarUrl,
        'content': title,
        'postType': 'live',
        'likes': 0,
        'comments': 0,
        'reposts': 0,
        'impressions': 0,
        'createdAt': DateTime.now().toIso8601String(),
        'mediaUrls': [],
        'title': title,
      };
      await AppwriteService.createPost(data);
      if (!mounted) return;
      _titleController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Live started')),
      );
      await _loadLiveSessions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to start live: $e')));
      }
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadLiveSessions,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Go Live',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: 'Live title',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.videocam),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isStarting ? null : _startLive,
                icon: const Icon(Icons.wifi_tethering),
                label: Text(_isStarting ? 'Starting...' : 'Start Live'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1DA1F2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Live Now',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            else if (_liveSessions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No live sessions yet. Start one!'),
              )
            else
              ..._liveSessions.map(
                (row) => ListTile(
                  leading: const Icon(Icons.wifi_tethering),
                  title: Text(row.data['title'] as String? ?? 'Live'),
                  subtitle: Text(row.data['username'] as String? ?? 'Unknown'),
                  trailing: const Text('Join'),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Joining live (placeholder)...')),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
