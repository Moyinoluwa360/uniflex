import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../services/admin_providers.dart';

/// Admin Analytics — fuller metrics than the Dashboard snapshot: user
/// counts, orders + revenue by period, top items, completion rate, and
/// per-rider delivery performance.
class AdminAnalyticsScreen extends ConsumerWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final analyticsAsync = ref.watch(adminAnalyticsProvider);

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Analytics',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(adminAnalyticsProvider),
          ),
        ],
      ),
      body: analyticsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load analytics.',
          onRetry: () => ref.invalidate(adminAnalyticsProvider),
        ),
        data: (data) => ListView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          children: [
            // ── User counts ──────────────────────────────────────────
            Text('Users', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    label: 'Students',
                    value: '${data['totalStudents'] ?? 0}',
                    icon: Icons.school_outlined,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.cardGap),
                Expanded(
                  child: _MetricCard(
                    label: 'Riders',
                    value: '${data['totalRiders'] ?? 0}',
                    icon: Icons.two_wheeler_outlined,
                    color: AppColors.orange,
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── Orders ───────────────────────────────────────────────
            Text('Orders', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            _PeriodRow(
              label: 'Today',
              orders: data['ordersToday'] as int? ?? 0,
              revenue: (data['revenueToday'] as num?)?.toDouble() ?? 0,
            ),
            _PeriodRow(
              label: 'This week',
              orders: data['ordersThisWeek'] as int? ?? 0,
              revenue: (data['revenueThisWeek'] as num?)?.toDouble() ?? 0,
            ),
            _PeriodRow(
              label: 'This month',
              orders: data['ordersThisMonth'] as int? ?? 0,
              revenue: (data['revenueThisMonth'] as num?)?.toDouble() ?? 0,
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── Completion rate ───────────────────────────────────────
            Text('Completion rate', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            _CompletionCard(
              completed: data['completedCount'] as int? ?? 0,
              cancelled: data['cancelledCount'] as int? ?? 0,
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── Status breakdown ─────────────────────────────────────
            Text('Orders by status (this month)',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            _StatusBreakdownCard(
                byStatus: data['byStatus'] as Map<String, dynamic>? ?? {}),

            const SizedBox(height: AppSpacing.lg),

            // ── Top-selling items ────────────────────────────────────
            Text('Top-selling items', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            _TopItemsList(
                items: (data['topItems'] as List?)?.cast<Map<String, dynamic>>() ?? []),

            const SizedBox(height: AppSpacing.lg),

            // ── Rider performance ────────────────────────────────────
            Text('Rider performance (this month)',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            _RiderPerformanceList(
                riders: (data['riderPerformance'] as List?)
                        ?.cast<Map<String, dynamic>>() ??
                    []),

            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodRow extends StatelessWidget {
  const _PeriodRow({
    required this.label,
    required this.orders,
    required this.revenue,
  });

  final String label;
  final int orders;
  final double revenue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: theme.textTheme.bodyMedium),
            ),
            Text(
              '$orders orders',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              '₦${revenue.toStringAsFixed(0)}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.emerald,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletionCard extends StatelessWidget {
  const _CompletionCard({
    required this.completed,
    required this.cancelled,
  });

  final int completed;
  final int cancelled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = completed + cancelled;
    final rate = total == 0 ? 0.0 : completed / total;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Completed', style: theme.textTheme.bodyMedium),
              Text(
                '$completed',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.emerald,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Cancelled', style: theme.textTheme.bodyMedium),
              Text(
                '$cancelled',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: rate,
              backgroundColor:
                  AppColors.error.withValues(alpha: 0.15),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.emerald),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${(rate * 100).toStringAsFixed(1)}% completion rate',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBreakdownCard extends StatelessWidget {
  const _StatusBreakdownCard({required this.byStatus});

  final Map<String, dynamic> byStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = [
      ('Placed', byStatus['placed'] as int? ?? 0, AppColors.info),
      ('Preparing', byStatus['preparing'] as int? ?? 0, AppColors.warning),
      ('Ready', byStatus['ready'] as int? ?? 0, AppColors.emerald),
      ('Out for Delivery',
          byStatus['out_for_delivery'] as int? ?? 0, AppColors.orange),
      ('Completed', byStatus['completed'] as int? ?? 0, AppColors.emerald),
      ('Cancelled', byStatus['cancelled'] as int? ?? 0, AppColors.error),
    ];

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          for (int i = 0; i < entries.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: entries[i].$3,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child:
                        Text(entries[i].$1, style: theme.textTheme.bodyMedium),
                  ),
                  Text(
                    '${entries[i].$2}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (i < entries.length - 1)
              const Divider(height: 1, indent: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}

class _TopItemsList extends StatelessWidget {
  const _TopItemsList({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return Text(
        'No completed orders yet.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${i + 1}.',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      items[i]['name'] as String? ?? '',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    '${items[i]['quantity'] ?? 0} sold',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (i < items.length - 1)
              const Divider(height: 1, indent: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}

class _RiderPerformanceList extends StatelessWidget {
  const _RiderPerformanceList({required this.riders});

  final List<Map<String, dynamic>> riders;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (riders.isEmpty) {
      return Text(
        'No deliveries completed this month.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          for (int i = 0; i < riders.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(Icons.two_wheeler_outlined,
                      size: 18,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      riders[i]['name'] as String? ?? 'Unknown',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    '${riders[i]['deliveries'] ?? 0} deliveries',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.emerald,
                    ),
                  ),
                ],
              ),
            ),
            if (i < riders.length - 1)
              const Divider(height: 1, indent: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}
