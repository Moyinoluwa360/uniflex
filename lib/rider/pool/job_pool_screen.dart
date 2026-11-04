import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/order.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../delivery/active_delivery_screen.dart';
import '../delivery/group_delivery_screen.dart';
import '../services/rider_providers.dart';
import 'pool_group.dart';
import 'pool_order.dart';

/// Live job pool — shows all unassigned pool-eligible orders.
/// Riders tap "Accept" to claim an order first-come-first-served.
class JobPoolScreen extends ConsumerWidget {
  const JobPoolScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final poolAsync = ref.watch(jobPoolProvider);
    final groupPoolAsync = ref.watch(groupPoolProvider);
    final activeOrders =
        ref.watch(activeDeliveriesProvider).valueOrNull ?? [];
    final groups = groupPoolAsync.valueOrNull ?? [];

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
          onRetry: () {
            ref.invalidate(jobPoolProvider);
            ref.invalidate(groupPoolProvider);
          },
        ),
        data: (pool) {
          if (pool.isEmpty && groups.isEmpty && activeOrders.isEmpty) {
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

          final hasActiveBanner = activeOrders.isNotEmpty;
          // Combined list: active banner + group cards + individual order cards.
          final bannerCount = hasActiveBanner ? 1 : 0;
          final totalItems = bannerCount + groups.length + pool.length;

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.md,
              AppSpacing.screenGutter,
              AppSpacing.xl,
            ),
            itemCount: totalItems,
            itemBuilder: (ctx, i) {
              if (hasActiveBanner && i == 0) {
                return _ActiveDeliveriesBanner(orders: activeOrders);
              }
              final adjusted = i - bannerCount;
              if (adjusted < groups.length) {
                return _PoolGroupCard(poolGroup: groups[adjusted]);
              }
              final poolIndex = adjusted - groups.length;
              return _PoolOrderCard(poolOrder: pool[poolIndex]);
            },
          );
        },
      ),
    );
  }
}

/// Compact banner shown at the top of the pool when the rider has active
/// deliveries. Tapping it opens the delivery screen.
class _ActiveDeliveriesBanner extends StatelessWidget {
  const _ActiveDeliveriesBanner({required this.orders});
  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ActiveDeliveryScreen(orderId: orders.first.id),
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
              const Icon(Icons.delivery_dining,
                  color: AppColors.orange, size: 24),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  orders.length == 1
                      ? 'You have an active delivery'
                      : 'You have ${orders.length} active deliveries',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.orange),
            ],
          ),
        ),
      ),
    );
  }
}

class _PoolOrderCard extends ConsumerStatefulWidget {
  const _PoolOrderCard({required this.poolOrder});

  final PoolOrder poolOrder;

  @override
  ConsumerState<_PoolOrderCard> createState() => _PoolOrderCardState();
}

class _PoolOrderCardState extends ConsumerState<_PoolOrderCard> {
  bool _isAccepting = false;

  Future<void> _accept() async {
    setState(() => _isAccepting = true);
    try {
      await ref
          .read(riderServiceProvider)
          .acceptOrder(widget.poolOrder.order.id);
      // Navigate to active delivery screen on success.
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                ActiveDeliveryScreen(orderId: widget.poolOrder.order.id),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().contains('already taken')
                  ? 'Order already taken by another rider.'
                  : 'Could not accept: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final po = widget.poolOrder;
    final order = po.order;

    final badgeColor = switch (po.orderTypeLabel) {
      'Errand' => AppColors.accentViolet,
      'Partner Food' => AppColors.info,
      _ => theme.colorScheme.primary,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    po.orderTypeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: badgeColor,
                      fontWeight: FontWeight.w600,
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

            // ── Pickup ────────────────────────────────────────────────
            _InfoRow(
              icon: Icons.store_outlined,
              label: 'Pickup',
              value: po.pickupAddress != null
                  ? '${po.pickupName} · ${po.pickupAddress}'
                  : po.pickupName,
            ),

            const SizedBox(height: AppSpacing.sm),

            // ── Deliver to ────────────────────────────────────────────
            _InfoRow(
              icon: Icons.location_on_outlined,
              label: 'Deliver to',
              value: order.deliveryLocation ?? '—',
            ),

            // ── Errand item description ───────────────────────────────
            if (order.isErrand && order.notes != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _InfoRow(
                icon: Icons.description_outlined,
                label: 'Item',
                value: order.notes!,
              ),
            ],

            // ── Student note ─────────────────────────────────────────
            if (!order.isErrand && order.notes != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _InfoRow(
                icon: Icons.sticky_note_2_outlined,
                label: 'Note',
                value: order.notes!,
              ),
            ],

            const SizedBox(height: AppSpacing.md),

            // ── Amount + Accept ───────────────────────────────────────
            Row(
              children: [
                // Hide monetary amounts for partner/around orders —
                // the final cost isn't known until after sourcing.
                if (order.source == 'uniflex')
                  Text(
                    '₦${order.totalAmount.toStringAsFixed(0)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppColors.emerald,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  Text(
                    'Amount TBD',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                const Spacer(),
                SizedBox(
                  height: 40,
                  child: FilledButton(
                    onPressed: _isAccepting ? null : _accept,
                    child: _isAccepting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.pureWhite,
                            ),
                          )
                        : const Text('Accept'),
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
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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

/// Card for a delivery group in the pool (Round 7 multi-vendor).
class _PoolGroupCard extends ConsumerStatefulWidget {
  const _PoolGroupCard({required this.poolGroup});

  final PoolGroup poolGroup;

  @override
  ConsumerState<_PoolGroupCard> createState() => _PoolGroupCardState();
}

class _PoolGroupCardState extends ConsumerState<_PoolGroupCard> {
  bool _isAccepting = false;

  Future<void> _accept() async {
    setState(() => _isAccepting = true);
    try {
      await ref
          .read(riderServiceProvider)
          .acceptDeliveryGroup(widget.poolGroup.group.id);
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GroupDeliveryScreen(
                groupId: widget.poolGroup.group.id),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().contains('Already accepted')
                  ? 'Already taken by another rider.'
                  : 'Could not accept: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pg = widget.poolGroup;
    final group = pg.group;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: AppColors.emerald.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.emerald.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    'Multi-Vendor (${pg.legCount} stops)',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.emerald,
                      fontWeight: FontWeight.w600,
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
            _InfoRow(
              icon: Icons.storefront,
              label: 'Vendors',
              value: pg.vendorNames.join(', '),
            ),
            const SizedBox(height: AppSpacing.sm),
            _InfoRow(
              icon: Icons.location_on_outlined,
              label: 'Deliver to',
              value: group.deliveryLocation ?? '—',
            ),
            if (group.studentNote != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _InfoRow(
                icon: Icons.sticky_note_2_outlined,
                label: 'Note',
                value: group.studentNote!,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Text(
                  switch (group.deliveryType) {
                    'pickup' => 'Pickup',
                    _ => 'Delivery',
                  },
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  height: 40,
                  child: FilledButton(
                    onPressed: _isAccepting ? null : _accept,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                    ),
                    child: _isAccepting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.pureWhite,
                            ),
                          )
                        : const Text('Accept Group'),
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
