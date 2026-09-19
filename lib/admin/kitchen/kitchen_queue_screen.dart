import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/order.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../services/admin_providers.dart';
import '../services/admin_service.dart';

/// The kitchen queue — live view of all Uniflex-source orders currently
/// in the kitchen stages (placed / preparing / ready). Updates via
/// Supabase Realtime without any manual refresh.
///
/// Only source='uniflex' orders appear here; partner vendor orders are
/// fulfilled externally and never enter the kitchen queue.
class KitchenQueueScreen extends ConsumerWidget {
  const KitchenQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ordersAsync = ref.watch(kitchenOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kitchen Queue'),
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
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not connect to the queue. Check your connection.',
          onRetry: () => ref.invalidate(kitchenOrdersProvider),
        ),
        data: (orders) {
          if (orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 56,
                    color: AppColors.emerald,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Queue is clear',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'No active orders right now.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            );
          }

          // Group by status for visual separation
          final placed = orders
              .where((o) => o.order.status == OrderStatus.placed)
              .toList();
          final preparing = orders
              .where((o) => o.order.status == OrderStatus.preparing)
              .toList();
          final ready = orders
              .where((o) => o.order.status == OrderStatus.ready)
              .toList();

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            children: [
              if (placed.isNotEmpty) ...[
                _SectionHeader(
                  label: 'Scheduled',
                  count: placed.length,
                  color: AppColors.orange,
                ),
                const SizedBox(height: AppSpacing.sm),
                ...placed.map((ko) => _KitchenOrderCard(kitchenOrder: ko)),
              ],
              if (preparing.isNotEmpty) ...[
                if (placed.isNotEmpty) const SizedBox(height: AppSpacing.lg),
                _SectionHeader(
                  label: 'Preparing',
                  count: preparing.length,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: AppSpacing.sm),
                ...preparing.map((ko) => _KitchenOrderCard(kitchenOrder: ko)),
              ],
              if (ready.isNotEmpty) ...[
                if (placed.isNotEmpty || preparing.isNotEmpty)
                  const SizedBox(height: AppSpacing.lg),
                _SectionHeader(
                  label: 'Ready',
                  count: ready.length,
                  color: AppColors.emerald,
                ),
                const SizedBox(height: AppSpacing.sm),
                ...ready.map((ko) => _KitchenOrderCard(kitchenOrder: ko)),
              ],
              const SizedBox(height: AppSpacing.xl),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: theme.textTheme.titleSmall),
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 1,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _KitchenOrderCard extends ConsumerStatefulWidget {
  const _KitchenOrderCard({required this.kitchenOrder});

  final KitchenOrder kitchenOrder;

  @override
  ConsumerState<_KitchenOrderCard> createState() => _KitchenOrderCardState();
}

class _KitchenOrderCardState extends ConsumerState<_KitchenOrderCard> {
  bool _isAdvancing = false;
  bool _expanded = false;

  Future<void> _advance() async {
    final order = widget.kitchenOrder.order;
    final nextStatus = switch (order.status) {
      OrderStatus.placed => 'preparing',
      OrderStatus.preparing => 'ready',
      _ => null,
    };
    if (nextStatus == null) return;

    setState(() => _isAdvancing = true);
    try {
      await ref
          .read(adminServiceProvider)
          .updateOrderStatus(order.id, nextStatus);
      // The kitchenOrdersProvider stream will re-emit automatically via
      // Supabase Realtime — no manual invalidation needed.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isAdvancing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = widget.kitchenOrder.order;
    final items = widget.kitchenOrder.items;
    final statusColor = _statusColor(order.status);

    final nextLabel = switch (order.status) {
      OrderStatus.placed => 'Start Preparing',
      OrderStatus.preparing => 'Mark Ready',
      _ => null,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // ── Card header ─────────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  // Status dot
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // Order ID + time
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
                          _timeAgo(order.createdAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // BULK badge (Phase 6)
                  if (order.isBulk) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        'BULK',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.orange,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  // Delivery type badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          order.isForDelivery
                              ? Icons.delivery_dining_outlined
                              : Icons.storefront_outlined,
                          size: 12,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          switch (order.deliveryType) {
                            'campus_delivery' => 'Campus',
                            'hostel_delivery' => 'Hostel',
                            'delivery' => 'Delivery',
                            _ => 'Pickup',
                          },
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded items ───────────────────────────────────────────
          if (_expanded && items.isNotEmpty) ...[
            const Divider(height: 1, indent: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Column(
                children: items.map((item) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Text(
                          '${item.quantity}×',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.productName,
                                  style: theme.textTheme.bodySmall),
                              if (item.optionsSummary.isNotEmpty)
                                Text(
                                  item.optionsSummary,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          if (_expanded && order.deliveryLocation != null) ...[
            const Divider(height: 1, indent: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.deliveryLocation!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Advance button ───────────────────────────────────────────
          if (nextLabel != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isAdvancing ? null : _advance,
                  style: FilledButton.styleFrom(
                    backgroundColor: statusColor,
                  ),
                  child: _isAdvancing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.pureWhite,
                          ),
                        )
                      : Text(nextLabel),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(OrderStatus status) {
    return switch (status) {
      OrderStatus.placed => AppColors.orange,
      OrderStatus.preparing => Theme.of(context).colorScheme.primary,
      OrderStatus.ready => AppColors.emerald,
      _ => Theme.of(context).colorScheme.outline,
    };
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    return '${diff.inHours}h ago';
  }
}
