import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/services/auth/auth_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../jobs/active_jobs_screen.dart';
import '../jobs/rider_job.dart';
import '../services/rider_providers.dart';
import '../../shared/utils/app_error_mapper.dart';

class RiderDashboardScreen extends ConsumerStatefulWidget {
  const RiderDashboardScreen({super.key});

  @override
  ConsumerState<RiderDashboardScreen> createState() =>
      _RiderDashboardScreenState();
}

class _RiderDashboardScreenState extends ConsumerState<RiderDashboardScreen> {
  bool _isTogglingOnline = false;

  Future<void> _toggleOnline(bool current) async {
    setState(() => _isTogglingOnline = true);
    try {
      await ref.read(riderServiceProvider).toggleOnline(!current);
      ref.invalidate(riderStatsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update status. ${AppErrorMapper.map(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isTogglingOnline = false);
    }
  }

  void _openActive(int food, int errands) {
    switch (activeJobsTarget(food: food, errands: errands)) {
      case ActiveJobsTarget.chooser:
        showActiveJobsChooser(context, food: food, errands: errands);
      case ActiveJobsTarget.errands:
        openActiveJobsList(context, RiderJobKind.errand);
      case ActiveJobsTarget.food:
        openActiveJobsList(context, RiderJobKind.food);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final statsAsync = ref.watch(riderStatsProvider);
    final activeJobs =
        ref.watch(riderActiveJobsProvider).valueOrNull ?? const <RiderJob>[];
    final activeFood = activeJobs.where((j) => j.isFood).length;
    final activeErrands = activeJobs.where((j) => j.isErrand).length;

    final isOnline = statsAsync.valueOrNull?['is_online'] as bool? ?? false;
    final todayCount =
        (statsAsync.valueOrNull?['today_completed'] as num?)?.toInt() ?? 0;
    final totalCount =
        (statsAsync.valueOrNull?['total_completed'] as num?)?.toInt() ?? 0;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 110,
            pinned: true,
            backgroundColor: theme.colorScheme.primary,
            actions: [
              IconButton(
                icon: Icon(Icons.refresh, color: context.colors.onBrand),
                tooltip: 'Refresh',
                onPressed: () => ref.invalidate(riderStatsProvider),
              ),
            ],
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
                        color: context.colors.onBrand.withValues(alpha: 0.8),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Online toggle card ───────────────────────────────
                  _OnlineToggleCard(
                    isOnline: isOnline,
                    isLoading: _isTogglingOnline || statsAsync.isLoading,
                    onToggle: () => _toggleOnline(isOnline),
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // ── Stats ────────────────────────────────────────────
                  Text("Today's stats", style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          key: const ValueKey('active-jobs-card'),
                          label: 'Active jobs',
                          value: '${activeFood + activeErrands}',
                          icon: Icons.delivery_dining,
                          color: context.colors.statusAmber,
                          onTap: () => _openActive(activeFood, activeErrands),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.cardGap),
                      Expanded(
                        child: _StatCard(
                          label: 'Today',
                          value: '$todayCount',
                          icon: Icons.check_circle_outline,
                          color: context.colors.brandText,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.cardGap),
                      Expanded(
                        child: _StatCard(
                          label: 'All time',
                          value: '$totalCount',
                          icon: Icons.history_outlined,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnlineToggleCard extends StatelessWidget {
  const _OnlineToggleCard({
    required this.isOnline,
    required this.isLoading,
    required this.onToggle,
  });

  final bool isOnline;
  final bool isLoading;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        isOnline ? context.colors.brandText : theme.colorScheme.outline;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOnline ? 'You are online' : 'You are offline',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  isOnline
                      ? 'New delivery requests will appear in Jobs'
                      : 'Go online to start accepting deliveries',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Switch(
                  value: isOnline,
                  onChanged: (_) => onToggle(),
                ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
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
    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: onTap,
      child: card,
    );
  }
}
