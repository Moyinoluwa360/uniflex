import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/navigation/refresh_on_tab_visible.dart';
import '../dashboard/money_cards.dart';
import '../services/admin_providers.dart';
import '../services/stats_live.dart';

/// The Analytics tab's position in the super-admin bottom nav.
const int kAnalyticsTabIndex = 3;

/// Admin Analytics — fuller than the Dashboard: orders by period, fees and
/// food payments (two separate numbers), completion rate, orders by status,
/// top-selling items, rider performance and user counts.
///
/// All figures come from `get_admin_analytics()` — the same one-entry-per-
/// checkout, paid-only, Nigerian-day rules as the dashboard.
class AdminAnalyticsScreen extends ConsumerStatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  ConsumerState<AdminAnalyticsScreen> createState() =>
      _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends ConsumerState<AdminAnalyticsScreen>
    with StatsLiveRefresh<AdminAnalyticsScreen> {
  void _refresh() => ref.invalidate(adminAnalyticsProvider);

  Future<void> _pullToRefresh() async {
    ref.invalidate(adminAnalyticsProvider);
    try {
      await ref.read(adminAnalyticsProvider.future);
    } catch (_) {
      // The error state is shown by the screen itself.
    }
  }

  @override
  Widget build(BuildContext context) {
    final analyticsAsync = ref.watch(adminAnalyticsProvider);
    listenForOrderChanges(_refresh);
    final data = analyticsAsync.valueOrNull;

    return RefreshOnTabVisible(
      tabIndex: kAnalyticsTabIndex,
      onVisible: _refresh,
      child: Scaffold(
        appBar: UniflexAppBar(
          title: 'Analytics',
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _refresh,
            ),
          ],
        ),
        body: data != null
            ? RefreshIndicator(
                onRefresh: _pullToRefresh,
                child: AnalyticsView(data: data),
              )
            : analyticsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => RetrySection(
                  message: 'Could not load analytics.',
                  onRetry: _refresh,
                ),
                data: (d) => RefreshIndicator(
                  onRefresh: _pullToRefresh,
                  child: AnalyticsView(data: d),
                ),
              ),
      ),
    );
  }
}

/// Pure rendering of the analytics map (also driven directly by tests).
class AnalyticsView extends StatelessWidget {
  const AnalyticsView({super.key, required this.data});

  final Map<String, dynamic> data;

  List<Map<String, dynamic>> _list(String key) =>
      (data[key] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ??
      const [];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final users = Map<String, dynamic>.from(data['users'] as Map? ?? {});
    final byStatus = Map<String, dynamic>.from(data['by_status'] as Map? ?? {});
    final rate = data['completion_rate'];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      children: [
        Text('Orders', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        _PeriodTable(
          rows: [
            (
              'Placed',
              statNum(data, 'orders_today'),
              statNum(data, 'orders_week'),
              statNum(data, 'orders_month')
            ),
            (
              'Completed',
              statNum(data, 'completed_today'),
              statNum(data, 'completed_week'),
              statNum(data, 'completed_month')
            ),
            (
              'Cancelled',
              statNum(data, 'cancelled_today'),
              statNum(data, 'cancelled_week'),
              statNum(data, 'cancelled_month')
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Money', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        PeriodMoneyCard(
          title: 'Fees collected',
          caption:
              'Delivery / commitment fees, service charges and errand fees',
          today: statNum(data, 'fees_today'),
          week: statNum(data, 'fees_week'),
          month: statNum(data, 'fees_month'),
          color: kFeesColor,
          icon: Icons.payments_outlined,
        ),
        const SizedBox(height: AppSpacing.cardGap),
        PeriodMoneyCard(
          title: 'Food payments',
          caption: 'Final food payments and pickup order payments',
          today: statNum(data, 'food_today'),
          week: statNum(data, 'food_week'),
          month: statNum(data, 'food_month'),
          color: kFoodColor,
          icon: Icons.restaurant_outlined,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Completion rate (this month)',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        _CompletionCard(
          completed: statNum(data, 'completed_month').toInt(),
          cancelled: statNum(data, 'cancelled_month').toInt(),
          rate: rate is num ? rate.toDouble() : null,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Orders by status (placed this month)',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        _StatusBreakdownCard(byStatus: byStatus),
        const SizedBox(height: AppSpacing.lg),
        Text('Top-selling items (completed this month)',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        _TopItemsList(items: _list('top_items')),
        const SizedBox(height: AppSpacing.lg),
        Text('Rider performance (completed this month)',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        _RiderPerformanceList(riders: _list('rider_performance')),
        const SizedBox(height: AppSpacing.lg),
        Text('Users', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Students',
                value: '${statNum(users, 'students').toInt()}',
                icon: Icons.school_outlined,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.cardGap),
            Expanded(
              child: _MetricCard(
                label: 'Riders',
                value: '${statNum(users, 'riders').toInt()}',
                icon: Icons.two_wheeler_outlined,
                color: AppColors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const StatsFootnote(),
        const SizedBox(height: AppSpacing.xl),
      ],
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

/// Today / week / month counts as a small table.
class _PeriodTable extends StatelessWidget {
  const _PeriodTable({required this.rows});

  final List<(String, num, num, num)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final head = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
      fontWeight: FontWeight.w700,
    );
    Widget cell(String t, {TextStyle? style}) => SizedBox(
          width: 64,
          child: Text(t, textAlign: TextAlign.end, style: style),
        );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          Row(children: [
            const Expanded(child: SizedBox()),
            cell('Today', style: head),
            cell('Week', style: head),
            cell('Month', style: head),
          ]),
          const SizedBox(height: AppSpacing.xs),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text(r.$1, style: theme.textTheme.bodyMedium)),
                cell('${r.$2.toInt()}',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                cell('${r.$3.toInt()}', style: theme.textTheme.bodyMedium),
                cell('${r.$4.toInt()}', style: theme.textTheme.bodyMedium),
              ]),
            ),
        ],
      ),
    );
  }
}

class _CompletionCard extends StatelessWidget {
  const _CompletionCard({
    required this.completed,
    required this.cancelled,
    required this.rate,
  });

  final int completed;
  final int cancelled;

  /// Percentage 0–100 from the database; null when nothing has finished yet.
  final double? rate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = ((rate ?? 0) / 100).clamp(0.0, 1.0);

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
              value: fraction,
              backgroundColor: AppColors.error.withValues(alpha: 0.15),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.emerald),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            rate == null
                ? 'No finished orders yet this month'
                : '${rate!.toStringAsFixed(1)}% completion rate',
            key: const ValueKey('completion-rate-text'),
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

  // Delivery checkouts and pickup/errand orders share one list; statuses
  // that don't exist for a kind simply stay 0 and are hidden.
  static const _labels = <String, (String, Color)>{
    'placed': ('Placed', AppColors.info),
    'commitment_paid': ('Waiting for rider', AppColors.orange),
    'rider_accepted': ('Rider accepted', AppColors.warning),
    'preparing': ('Preparing', AppColors.warning),
    'being_sourced': ('Being sourced', AppColors.warning),
    'ready': ('Ready', AppColors.emerald),
    'ready_for_pickup': ('Ready for pickup', AppColors.emerald),
    'awaiting_final_payment': ('Awaiting final payment', AppColors.info),
    'out_for_delivery': ('Out for delivery', AppColors.orange),
    'completed': ('Completed', AppColors.emerald),
    'cancelled': ('Cancelled', AppColors.error),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = <(String, int, Color)>[
      for (final e in _labels.entries)
        if (statNum(byStatus, e.key) > 0)
          (e.value.$1, statNum(byStatus, e.key).toInt(), e.value.$2),
    ];

    if (entries.isEmpty) {
      return Text(
        'No orders this month yet.',
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
        'No completed orders yet this month.',
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
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
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
                      riders[i]['name'] as String? ?? 'Rider',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    '${riders[i]['completed'] ?? 0} completed',
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
