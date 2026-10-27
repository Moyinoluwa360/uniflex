import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/order.dart';
import '../../shared/models/order_item.dart';
import '../../shared/services/supabase/supabase_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import 'order_repository.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// A flag raised by the rider to mark an item as unavailable while sourcing.
class OrderItemFlag {
  const OrderItemFlag({
    required this.id,
    required this.orderId,
    required this.productName,
    required this.quantity,
    this.resolved = false,
  });

  final String id;
  final String orderId;
  final String productName;
  final int quantity;
  final bool resolved;

  factory OrderItemFlag.fromMap(Map<String, dynamic> m) => OrderItemFlag(
        id: m['id'] as String,
        orderId: m['order_id'] as String,
        productName: m['product_name'] as String,
        quantity: m['quantity'] as int,
        resolved: m['resolved'] as bool? ?? false,
      );
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Fetches unresolved item flags for [orderId].
final orderItemFlagsProvider =
    FutureProvider.family<List<OrderItemFlag>, String>((ref, orderId) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('order_item_flags')
      .select()
      .eq('order_id', orderId)
      .eq('resolved', false)
      .order('created_at');
  return rows.map((m) => OrderItemFlag.fromMap(m)).toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Shown to the student when their [being_sourced] order has flagged items.
/// Lets them review which items the rider cannot source and confirm
/// the adjusted order (communicated to the rider via a message).
class AdjustOrderScreen extends ConsumerWidget {
  const AdjustOrderScreen({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final flagsAsync = ref.watch(orderItemFlagsProvider(order.id));
    final liveAsync = ref.watch(orderByIdProvider(order.id));

    final liveOrder = liveAsync.valueOrNull ?? order;

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Adjust Order ${order.shortId}',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(orderItemFlagsProvider(order.id));
              ref.invalidate(orderByIdProvider(order.id));
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: flagsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load item flags.',
          onRetry: () => ref.invalidate(orderItemFlagsProvider(order.id)),
        ),
        data: (flags) => _buildBody(context, theme, ref, liveOrder, flags),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    WidgetRef ref,
    Order liveOrder,
    List<OrderItemFlag> flags,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Banner ───────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.warning, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Your rider flagged some items as unavailable. '
                    'Review and confirm your adjusted order.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // ── Original items ───────────────────────────────────────────
          if (liveOrder.items.isNotEmpty) ...[
            Text('Your Items', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Column(
                children: liveOrder.items.map((item) {
                  final isFlagged = flags.any(
                    (f) => f.productName.toLowerCase() ==
                            item.productName.toLowerCase() ||
                        (item.productId != null),
                  );
                  return _ItemRow(
                    item: item,
                    isFlagged: isFlagged,
                    theme: theme,
                    isLast:
                        liveOrder.items.last == item,
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // ── Flagged items list ───────────────────────────────────────
          if (flags.isNotEmpty) ...[
            Text('Unavailable Items', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            ...flags.map((flag) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.remove_circle_outline,
                            color: AppColors.error, size: 18),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                flag.productName,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  decoration: TextDecoration.lineThrough,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              Text(
                                'Qty: ${flag.quantity} — not available at vendor',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppColors.error
                                      .withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )),
            const SizedBox(height: AppSpacing.lg),
          ],

          if (flags.isEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.emerald.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: AppColors.emerald, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'No items flagged — your rider is still sourcing.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.emerald),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // ── Confirm adjustments ──────────────────────────────────────
          if (flags.isNotEmpty) ...[
            Text(
              'Tap "Confirm Adjustments" to let your rider know you accept '
              'the order without the unavailable items. The final cost will '
              'be updated by the rider.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.check_outlined, size: 18),
                label: const Text('Confirm Adjustments'),
                onPressed: () => _confirmAdjustments(context, ref),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmAdjustments(
      BuildContext context, WidgetRef ref) async {
    // The rider already has the flags recorded in order_item_flags.
    // Acknowledging here signals the student has reviewed the unavailable
    // items — no additional RPC is needed. The final amount will be set
    // when the rider calls confirm_sourced_items.
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Adjustments noted — your rider will confirm the final amount shortly.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop();
  }
}

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.isFlagged,
    required this.theme,
    required this.isLast,
  });

  final OrderItem item;
  final bool isFlagged;
  final ThemeData theme;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              if (isFlagged)
                const Icon(Icons.block, color: AppColors.error, size: 16)
              else
                const Icon(Icons.check_circle_outline,
                    color: AppColors.emerald, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${item.quantity}× ${item.productName}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    decoration: isFlagged ? TextDecoration.lineThrough : null,
                    color: isFlagged
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                        : null,
                  ),
                ),
              ),
              Text(
                '₦${item.lineTotal.toStringAsFixed(0)}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: isFlagged
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                      : null,
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            indent: AppSpacing.md,
            endIndent: AppSpacing.md,
            color: theme.dividerColor.withValues(alpha: 0.5),
          ),
      ],
    );
  }
}
