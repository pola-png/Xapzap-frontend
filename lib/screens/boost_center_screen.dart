import 'package:flutter/material.dart';
import 'package:appwrite/models.dart' as aw;

import '../services/boost_service.dart';
import '../services/appwrite_service.dart';
import '../services/storage_service.dart';
import '../models/post.dart';

class BoostCenterScreen extends StatefulWidget {
  const BoostCenterScreen({super.key});

  @override
  State<BoostCenterScreen> createState() => _BoostCenterScreenState();
}

class _BoostCenterScreenState extends State<BoostCenterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  bool _isGuest = true;
  List<aw.Row> _pending = [];
  List<aw.Row> _running = [];
  List<aw.Row> _history = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadBoosts();
    _subscribeRealtime();
  }

  Future<void> _loadBoosts() async {
    setState(() => _loading = true);
    try {
      final user = await AppwriteService.getCurrentUser();
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _isGuest = true;
          _loading = false;
        });
        return;
      }
      final pending = await BoostService.fetchBoostsForUser(
        user.$id,
        status: 'pending',
      );
      final running = await BoostService.fetchBoostsForUser(
        user.$id,
        status: 'running',
      );
      final completed = await BoostService.fetchBoostsForUser(
        user.$id,
        status: 'completed',
      );
      final failed = await BoostService.fetchBoostsForUser(
        user.$id,
        status: 'failed',
      );
      if (!mounted) return;
      setState(() {
        _isGuest = false;
        _pending = pending.rows;
        _running = running.rows;
        _history = [...completed.rows, ...failed.rows];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribeRealtime() {
    try {
      final channel =
          'databases.${AppwriteService.databaseId}.collections.${AppwriteService.postBoostsCollectionId}.documents';
      final sub = AppwriteService.realtime.subscribe([channel]);
      sub.stream.listen((event) async {
        if (!mounted) return;
        if (event.events.isEmpty) return;
        await _loadBoosts();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ads manager'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Running'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _isGuest
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Sign in to see your ads.'),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadBoosts,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildList(theme, _pending),
                  _buildList(theme, _running),
                  _buildList(theme, _history),
                ],
              ),
            ),
    );
  }

  Widget _buildList(ThemeData theme, List<aw.Row> rows) {
    if (rows.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SizedBox(height: 200, child: Center(child: Text('No ads here yet.'))),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final data = row.data;
        final status = (data['status'] as String?) ?? '';
        final amount = (data['amountUsd'] as num?)?.toDouble() ?? 0;
        final days = (data['days'] as int?) ?? 1;
        final target = (data['targetReach'] as int?) ?? 0;
        final delivered = (data['deliveredImpressions'] as int?) ?? 0;
        final progress = target > 0
            ? (delivered / target).clamp(0.0, 1.0)
            : 0.0;

        return FutureBuilder<aw.Row>(
          future: AppwriteService.getRow(
            AppwriteService.postsCollectionId,
            data['postId'] as String,
          ),
          builder: (context, snapshot) {
            Widget? subtitle;
            String title = 'Ad on post';
            if (snapshot.hasData) {
              final p = snapshot.data!;
              final pd = p.data;
              final kind =
                  (pd['postType'] ?? pd['type'] ?? pd['category']) as String?;
              final postTitle =
                  (pd['title'] as String?) ?? (pd['content'] as String?) ?? '';
              title = postTitle.isEmpty ? 'Ad on $kind post' : postTitle;
              final post = Post(
                id: p.$id,
                username: pd['username'] as String? ?? '',
                userAvatar: pd['userAvatar'] as String? ?? '',
                content: pd['content'] as String? ?? '',
                timestamp: DateTime.tryParse(p.$createdAt) ?? DateTime.now(),
                likes: pd['likes'] as int? ?? 0,
                comments: pd['comments'] as int? ?? 0,
                reposts: pd['reposts'] as int? ?? 0,
                impressions: pd['impressions'] as int? ?? 0,
                views: pd['views'] as int? ?? 0,
              );
              subtitle = Text(
                'Engagement: ${post.totalEngagement}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
            }

            final statusColor = _statusColor(theme, status);
            final statusLabel = status.isEmpty
                ? ''
                : status[0].toUpperCase() + status.substring(1);

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '\$${amount.toStringAsFixed(2)} · $days day(s)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      subtitle,
                    ],
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: theme.colorScheme.surfaceVariant
                          .withOpacity(0.4),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$delivered / $target reach delivered',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color _statusColor(ThemeData theme, String status) {
    switch (status.toLowerCase()) {
      case 'running':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'failed':
        return Colors.red;
      default:
        return theme.colorScheme.primary;
    }
  }
}
