import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/order.dart';
import '../../shared/services/auth/auth_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../delivery/active_delivery_screen.dart';
import '../services/rider_providers.dart';

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
          SnackBar(content: Text('Could not update status: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isTogglingOnline = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final statsAsync = ref.watch(riderStatsProvider);
    final activeAsync = ref.watch(activeDeliveryProvider);

    final isOnline = statsAsync.valueOrNull?['is_online'] as bool? ?? false;
    final todayCount = statsAsync.valueOrNull?['today_completed'] as int? ?? 0;
    final totalCount = statsAsync.valueOrNull?['total_completed'] as int? ?? 0;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 110,
            pinned: true,
            backgroundColor: theme.colorScheme.primary,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: AppColors.pureWhite),
                tooltip: 'Refresh',
                onPressed: () => ref.invalidate(riderStatsProvider),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(
                AppSpacing.screenGutter, 0, AppSpacing.screenGutter, AppSpacing.md,
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

                  // ── Active delivery card ─────────────────────────────
                  activeAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (activeOrder) {
                      if (activeOrder == null) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Active Delivery',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _ActiveDeliveryBanner(order: activeOrder),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                      );
                    },
                  ),

                  // ── Stats ────────────────────────────────────────────
                  Text("Today's stats", style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: 'Today',
                          value: '$todayCount',
                          icon: Icons.check_circle_outline,
                          color: AppColors.emerald,
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
    final color = isOnline ? AppColors.emerald : theme.colorScheme.outline;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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
                  activeThumbColor: AppColors.emerald,
                ),
        ],
      ),
    );
  }
}

class _ActiveDeliveryBanner extends ConsumerWidget {
  const _ActiveDeliveryBanner({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ActiveDeliveryScreen(orderId: order.id),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.delivery_dining, color: AppColors.orange, size: 28),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.shortId,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    order.deliveryLocation ?? '—',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
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
  }
}
