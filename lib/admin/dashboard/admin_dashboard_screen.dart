import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/services/auth/auth_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../services/admin_providers.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final statsAsync = ref.watch(dashboardStatsProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────
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
                      color: AppColors.pureWhite,
                    ),
                  ),
                  if (profile?.fullName != null)
                    Text(
                      profile!.fullName!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.pureWhite.withValues(alpha: 0.8),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: AppColors.pureWhite),
                tooltip: 'Refresh',
                onPressed: () => ref.invalidate(dashboardStatsProvider),
              ),
            ],
          ),

          // ── Stats grid ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              child: statsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (e, _) => RetrySection(
                  message: 'Could not load stats.',
                  onRetry: () => ref.invalidate(dashboardStatsProvider),
                ),
                data: (stats) => _StatsContent(stats: stats),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        ],
      ),
    );
  }
}

class _StatsContent extends StatelessWidget {
  const _StatsContent({required this.stats});

  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byStatus = stats['by_status'] as Map<String, dynamic>? ?? {};
    final todayTotal = stats['today_orders_total'] as int? ?? 0;
    final revenue = (stats['today_revenue'] as num?)?.toDouble() ?? 0.0;
    final pending = stats['pending_count'] as int? ?? 0;
    final completedToday = byStatus['completed'] as int? ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Today's overview", style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),

        // 2×2 stat grid
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.cardGap,
          mainAxisSpacing: AppSpacing.cardGap,
          childAspectRatio: 1.5,
          children: [
            _StatCard(
              label: "Orders today",
              value: '$todayTotal',
              icon: Icons.receipt_long_outlined,
              color: theme.colorScheme.primary,
            ),
            _StatCard(
              label: "Revenue",
              value: '₦${revenue.toStringAsFixed(0)}',
              icon: Icons.account_balance_wallet_outlined,
              color: AppColors.emerald,
            ),
            _StatCard(
              label: "Pending",
              value: '$pending',
              icon: Icons.hourglass_empty_outlined,
              color: AppColors.orange,
            ),
            _StatCard(
              label: "Completed",
              value: '$completedToday',
              icon: Icons.check_circle_outline,
              color: AppColors.accentViolet,
            ),
          ],
        ),

        const SizedBox(height: AppSpacing.lg),
        Text('Kitchen stages', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),

        _StatusBreakdown(byStatus: byStatus),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
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
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
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

class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown({required this.byStatus});

  final Map<String, dynamic> byStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = [
      ('Scheduled (Placed)', byStatus['placed'] as int? ?? 0, AppColors.orange),
      ('Preparing', byStatus['preparing'] as int? ?? 0, theme.colorScheme.primary),
      ('Ready', byStatus['ready'] as int? ?? 0, AppColors.emerald),
      ('Completed today', byStatus['completed'] as int? ?? 0, AppColors.accentViolet),
    ];

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 2,
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: rows[i].$3,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(rows[i].$1, style: theme.textTheme.bodyMedium),
                  ),
                  Text(
                    '${rows[i].$2}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (i < rows.length - 1)
              const Divider(height: 1, indent: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}
