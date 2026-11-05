import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../jobs/errand_job_screen.dart';
import '../jobs/food_job_screen.dart';
import '../services/rider_providers.dart';
import 'pool_group.dart';
import 'pool_order.dart';

/// Live job pool — shows all unassigned delivery groups and errand orders.
/// Riders tap "View →" on a card to open the detail screen, then accept from there.
class JobPoolScreen extends ConsumerWidget {
  const JobPoolScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final poolAsync = ref.watch(poolProvider);
    final activeWork = ref.watch(activeWorkProvider).valueOrNull;

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Available Jobs',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.emerald,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'Live',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.emerald,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: poolAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load jobs. Check your connection.',
          onRetry: () => ref.invalidate(poolProvider),
        ),
        data: (pool) {
          final groups = pool.groups;
          final errands = pool.errands;
          final activeGroups = activeWork?.groups ?? [];
          final activeErrands = activeWork?.errands ?? [];

          final hasGroupBanner = activeGroups.isNotEmpty;
          final hasErrandBanner = activeErrands.isNotEmpty;
          final bannerCount =
              (hasGroupBanner ? 1 : 0) + (hasErrandBanner ? 1 : 0);

          if (groups.isEmpty &&
              errands.isEmpty &&
              activeGroups.isEmpty &&
              activeErrands.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color:
                          theme.colorScheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.inbox_outlined,
                      size: 36,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'No jobs available',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'New orders will appear here automatically.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            );
          }

          final totalItems =
              bannerCount + groups.length + errands.length;

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.md,
              AppSpacing.screenGutter,
              AppSpacing.xl,
            ),
            itemCount: totalItems,
            itemBuilder: (ctx, i) {
              // Active food group banner.
              if (hasGroupBanner && i == 0) {
                return _ActiveGroupBanner(
                    groupId: activeGroups.first.id);
              }
              // Active errand banner.
              if (hasErrandBanner) {
                final errandBannerIndex = hasGroupBanner ? 1 : 0;
                if (i == errandBannerIndex) {
                  return _ActiveErrandBanner(
                      orderId: activeErrands.first.id);
                }
              }

              final adjusted = i - bannerCount;
              if (adjusted < groups.length) {
                return _PoolGroupCard(poolGroup: groups[adjusted]);
              }
              final errandIndex = adjusted - groups.length;
              return _PoolErrandCard(poolOrder: errands[errandIndex]);
            },
          );
        },
      ),
    );
  }
}

// ── Active banners ────────────────────────────────────────────────────────────

class _ActiveGroupBanner extends StatelessWidget {
  const _ActiveGroupBanner({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FoodJobScreen.active(groupId: groupId),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.emerald.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
                color: AppColors.emerald.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.delivery_dining,
                  color: AppColors.emerald, size: 24),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'You have an active food delivery',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.emerald,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.emerald),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveErrandBanner extends StatelessWidget {
  const _ActiveErrandBanner({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                ErrandJobScreen.active(orderId: orderId),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.accentViolet.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
                color: AppColors.accentViolet.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.directions_bike_outlined,
                  color: AppColors.accentViolet, size: 24),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'You have an active errand',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.accentViolet,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.accentViolet),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pool group card (food) ────────────────────────────────────────────────────

class _PoolGroupCard extends StatelessWidget {
  const _PoolGroupCard({required this.poolGroup});

  final PoolGroup poolGroup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pg = poolGroup;
    final group = pg.group;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
            color: AppColors.emerald.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row.
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.emerald.withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    'FOOD',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.emerald,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  group.shortId,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.md),

            // Vendors.
            _InfoRow(
              icon: Icons.storefront_outlined,
              label: pg.legCount == 1 ? 'Vendor' : 'Vendors',
              value: pg.vendorNames.isNotEmpty
                  ? pg.vendorNames.join(', ')
                  : '${pg.legCount} vendor${pg.legCount == 1 ? '' : 's'}',
            ),

            const SizedBox(height: AppSpacing.sm),

            // Drop-off.
            _InfoRow(
              icon: Icons.location_on_outlined,
              label: 'Deliver to',
              value: group.deliveryLocation ?? '—',
            ),

            const SizedBox(height: AppSpacing.sm),

            // Item count hint.
            _InfoRow(
              icon: Icons.shopping_bag_outlined,
              label: 'Stops',
              value: '${pg.legCount} stop${pg.legCount == 1 ? '' : 's'}',
            ),

            const SizedBox(height: AppSpacing.md),

            // View button.
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          FoodJobScreen.fromPool(poolGroup: pg),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('View'),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pool errand card ──────────────────────────────────────────────────────────

class _PoolErrandCard extends StatelessWidget {
  const _PoolErrandCard({required this.poolOrder});

  final PoolOrder poolOrder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final po = poolOrder;
    final order = po.order;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
            color: AppColors.accentViolet.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row.
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color:
                        AppColors.accentViolet.withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    'ERRAND',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.accentViolet,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  order.shortId,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.md),

            // Category (orderTypeLabel acts as category for now).
            _InfoRow(
              icon: Icons.category_outlined,
              label: 'Category',
              value: po.orderTypeLabel,
            ),

            const SizedBox(height: AppSpacing.sm),

            // Drop-off.
            _InfoRow(
              icon: Icons.location_on_outlined,
              label: 'Deliver to',
              value: order.deliveryLocation ?? '—',
            ),

            const SizedBox(height: AppSpacing.md),

            // View button.
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accentViolet,
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ErrandJobScreen.fromPool(order: order),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('View'),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared info row ───────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon,
            size: 16,
            color:
                theme.colorScheme.onSurface.withValues(alpha: 0.5)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface
                      .withValues(alpha: 0.5),
                ),
              ),
              Text(value, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
