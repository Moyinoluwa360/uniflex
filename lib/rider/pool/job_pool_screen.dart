import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../delivery/active_delivery_screen.dart';
import '../services/rider_providers.dart';
import 'pool_order.dart';

/// Live job pool — shows all unassigned pool-eligible orders.
/// Riders tap "Accept" to claim an order first-come-first-served.
class JobPoolScreen extends ConsumerWidget {
  const JobPoolScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final poolAsync = ref.watch(jobPoolProvider);
    final activeAsync = ref.watch(activeDeliveryProvider);

    // If rider has an active delivery, redirect to it instead.
    final hasActive = activeAsync.valueOrNull != null;

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Available Jobs',
        actions: [
          // Live indicator
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
      body: hasActive
          ? _ActiveDeliveryPrompt(
              orderId: activeAsync.valueOrNull!.id,
            )
          : poolAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => RetrySection(
                message: 'Could not load jobs. Check your connection.',
                onRetry: () => ref.invalidate(jobPoolProvider),
              ),
              data: (pool) {
                if (pool.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 56,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.3),
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

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    AppSpacing.md,
                    AppSpacing.screenGutter,
                    AppSpacing.xl,
                  ),
                  itemCount: pool.length,
                  itemBuilder: (ctx, i) =>
                      _PoolOrderCard(poolOrder: pool[i]),
                );
              },
            ),
    );
  }
}

/// Shown when the rider already has an active delivery — prevents
/// accepting a second one.
class _ActiveDeliveryPrompt extends StatelessWidget {
  const _ActiveDeliveryPrompt({required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delivery_dining,
                size: 56, color: AppColors.orange),
            const SizedBox(height: AppSpacing.md),
            Text('You have an active delivery',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Complete it before accepting a new job.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Go to Active Delivery'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ActiveDeliveryScreen(orderId: orderId),
                ),
              ),
            ),
          ],
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
      'Around' => AppColors.accentViolet,
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

            // ── Around item description ───────────────────────────────
            if (order.isAround && order.notes != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _InfoRow(
                icon: Icons.description_outlined,
                label: 'Item',
                value: order.notes!,
              ),
            ],

            const SizedBox(height: AppSpacing.md),

            // ── Amount + Accept ───────────────────────────────────────
            Row(
              children: [
                Text(
                  '₦${order.totalAmount.toStringAsFixed(0)}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.emerald,
                    fontWeight: FontWeight.w700,
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
        Icon(icon, size: 16,
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
