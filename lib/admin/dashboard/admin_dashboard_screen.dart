import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/services/auth/auth_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/navigation/refresh_on_tab_visible.dart';
import '../services/admin_providers.dart';
import '../services/stats_live.dart';
import 'money_cards.dart';

/// The Dashboard tab's position in the super-admin bottom nav.
const int kDashboardTabIndex = 0;

/// Today at a glance. Every number comes from `get_dashboard_stats()`:
/// one entry per checkout, paid only, errands included, Nigerian days.
///
/// It refetches: when the tab is opened, on pull-to-refresh, with the
/// refresh button, and shortly after any order changes underneath.
class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen>
    with StatsLiveRefresh<AdminDashboardScreen> {
  void _refresh() => ref.invalidate(dashboardStatsProvider);

  Future<void> _pullToRefresh() async {
    ref.invalidate(dashboardStatsProvider);
    try {
      await ref.read(dashboardStatsProvider.future);
    } catch (_) {
      // The error state is shown by the screen itself.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final statsAsync = ref.watch(dashboardStatsProvider);
    listenForOrderChanges(_refresh);

    // While a refetch is running keep showing the numbers we already have.
    final stats = statsAsync.valueOrNull;

    return RefreshOnTabVisible(
      tabIndex: kDashboardTabIndex,
      onVisible: _refresh,
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: _pullToRefresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 120,
                pinned: true,
                backgroundColor: theme.colorScheme.primary,
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    0,
                    AppSpacing.screenGutter,
                    AppSpacing.md,
                  ),
                  title: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dashboard',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: context.colors.onBrand,
                        ),
                      ),
                      if (profile?.fullName != null)
                        Text(
                          profile!.fullName!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                context.colors.onBrand.withValues(alpha: 0.8),
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  IconButton(
                    icon: Icon(Icons.refresh, color: context.colors.onBrand),
                    tooltip: 'Refresh',
                    onPressed: _refresh,
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.screenGutter),
                  child: stats != null
                      ? DashboardStatsView(stats: stats)
                      : statsAsync.when(
                          loading: () => const Center(
                            child: Padding(
                              padding: EdgeInsets.all(AppSpacing.xl),
                              child: CircularProgressIndicator(),
                            ),
                          ),
                          error: (e, _) => RetrySection(
                            message: 'Could not load stats.',
                            onRetry: _refresh,
                          ),
                          data: (s) => DashboardStatsView(stats: s),
                        ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pure rendering of the dashboard numbers (also driven directly by tests).
class DashboardStatsView extends StatelessWidget {
  const DashboardStatsView({super.key, required this.stats});

  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Today's overview", style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.cardGap,
          mainAxisSpacing: AppSpacing.cardGap,
          childAspectRatio: 1.5,
          children: [
            StatTile(
              label: 'Orders today',
              value: '${statNum(stats, 'orders_today').toInt()}',
              icon: Icons.receipt_long_outlined,
              color: theme.colorScheme.primary,
            ),
            StatTile(
              label: 'Pending / in progress',
              value: '${statNum(stats, 'pending_count').toInt()}',
              icon: Icons.hourglass_empty_outlined,
              color: context.colors.statusAmber,
            ),
            StatTile(
              label: 'Completed today',
              value: '${statNum(stats, 'completed_today').toInt()}',
              icon: Icons.check_circle_outline,
              color: context.colors.brandText,
            ),
            StatTile(
              label: 'Cancelled today',
              value: '${statNum(stats, 'cancelled_today').toInt()}',
              icon: Icons.cancel_outlined,
              color: context.colors.dangerText,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Money', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        PeriodMoneyCard(
          title: 'Fees collected',
          caption:
              'Delivery / commitment fees, service charges and errand fees',
          today: statNum(stats, 'fees_today'),
          week: statNum(stats, 'fees_week'),
          month: statNum(stats, 'fees_month'),
          color: context.colors.chartFees,
          icon: Icons.payments_outlined,
        ),
        const SizedBox(height: AppSpacing.cardGap),
        PeriodMoneyCard(
          title: 'Food payments',
          caption: 'Final food payments and pickup order payments',
          today: statNum(stats, 'food_today'),
          week: statNum(stats, 'food_week'),
          month: statNum(stats, 'food_month'),
          color: context.colors.chartFood,
          icon: Icons.restaurant_outlined,
        ),
        const SizedBox(height: AppSpacing.md),
        const StatsFootnote(),
      ],
    );
  }
}
