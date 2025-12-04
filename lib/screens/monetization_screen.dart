import 'package:flutter/material.dart';
import '../services/appwrite_service.dart';
import '../services/ad_revenue_service.dart';

class MonetizationScreen extends StatefulWidget {
  const MonetizationScreen({super.key});

  @override
  State<MonetizationScreen> createState() => _MonetizationScreenState();
}

class _MonetizationScreenState extends State<MonetizationScreen> {
  bool _loading = true;
  bool _isGuest = true;
  int _totalAdImpressions = 0;
  double _totalAdMicros = 0;
  Map<String, int> _countsByFormat = {};
  Map<String, int> _microsByFormat = {};
  final double _creatorShare = 0.40; // 40% to uploader

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final user = await AppwriteService.getCurrentUser();
      if (user == null) {
        if (mounted) setState(() => _isGuest = true);
        return;
      }
      // Use ad revenue events (not post impressions) for earnings.
      final totals = await AdRevenueService.getTotalsByFormat();
      final counts = await AdRevenueService.getCountsByFormat();
      final totalMicros = totals.values.fold<int>(0, (s, v) => s + v);
      final totalImps = counts.values.fold<int>(0, (s, v) => s + v);
      if (!mounted) return;
      setState(() {
        _isGuest = false;
        _microsByFormat = totals;
        _countsByFormat = counts;
        _totalAdMicros = totalMicros.toDouble();
        _totalAdImpressions = totalImps;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _estimatedGrossUsd => _totalAdMicros / 1e6;
  double get _estimatedCreatorUsd => _estimatedGrossUsd * _creatorShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monetization'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0.5,
      ),
      body: Container(
        width: double.infinity,
        color: theme.colorScheme.background,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _isGuest
            ? _buildGuest(theme)
            : RefreshIndicator(
                onRefresh: _loadData,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildSummary(theme),
                    const SizedBox(height: 16),
                    _buildBreakdown(theme),
                    const SizedBox(height: 16),
                    _buildLegend(theme),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildGuest(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48, color: Color(0xFF6B7280)),
            const SizedBox(height: 12),
            Text(
              'Sign in to see monetization stats',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Once you upload videos, we’ll track ad impressions and pay 40% of ad revenue to you.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Revenue share',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You earn 40% of ad revenue generated on your videos.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildMetric(
                theme,
                'Ad impressions',
                _totalAdImpressions.toString(),
              ),
              const SizedBox(width: 12),
              _buildMetric(
                theme,
                'Est. gross',
                '\$${_estimatedGrossUsd.toStringAsFixed(2)}',
              ),
              const SizedBox(width: 12),
              _buildMetric(
                theme,
                'Your 40%',
                '\$${_estimatedCreatorUsd.toStringAsFixed(2)}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.campaign_outlined, size: 18),
              label: const Text('View ads manager'),
              onPressed: () {
                Navigator.of(context).pushNamed('/boosts');
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(ThemeData theme, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdown(ThemeData theme) {
    if (_countsByFormat.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor),
        ),
        child: const Text(
          'No ad impressions yet. Upload videos to start earning.',
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'By ad format',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ..._countsByFormat.entries.map((entry) {
            final format = entry.key;
            final count = entry.value;
            final micros = _microsByFormat[format] ?? 0;
            final gross = micros / 1e6;
            final share = gross * _creatorShare;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          format,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$count impressions',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$${share.toStringAsFixed(2)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Gross \$${gross.toStringAsFixed(2)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLegend(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How payouts work',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text('• Ads run before Watch/Reels videos.'),
          const Text('• We calculate ad revenue per impression.'),
          const Text('• 40% of ad revenue for your videos goes to you.'),
          Text(
            'Estimates here reflect recorded ad revenue; actual payouts depend on live ad rates and platform reports.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
