import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/order.dart';
import '../../shared/services/notifications/notification_inbox_service.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/notify/message_customer_sheet.dart';
import '../services/admin_providers.dart';
import '../services/admin_service.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/widgets/buttons/app_button.dart';

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
    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Kitchen Queue',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: context.colors.brandText,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'Live',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: context.colors.brandText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: const KitchenQueueBody(),
    );
  }
}

/// The scrollable kitchen queue list — no Scaffold/AppBar. Used by both
/// [KitchenQueueScreen] and the Food tab inside [AdminOrdersScreen].
class KitchenQueueBody extends ConsumerWidget {
  const KitchenQueueBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ordersAsync = ref.watch(kitchenOrdersProvider);

    return ordersAsync.when(
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
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: context.colors.surfaceRaised,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle_outline,
                    size: 36,
                    color: context.colors.brandText,
                  ),
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

        // Group by status for visual separation. "Ready" is split by
        // fulfillment type (post-testing fixes, Section 12) since a
        // pickup order's next step is "hand it over" while a delivery
        // order's next step is "transfer to a rider" — the old single
        // "Ready" bucket had no room for either action.
        final beingSourced = orders
            .where((o) => o.order.status == OrderStatus.beingSourced)
            .toList();
        final placed =
            orders.where((o) => o.order.status == OrderStatus.placed).toList();
        final preparing = orders
            .where((o) => o.order.status == OrderStatus.preparing)
            .toList();
        final awaitingPayment = orders
            .where((o) => o.order.status == OrderStatus.awaitingFinalPayment)
            .toList();
        final readyForPickup = orders
            .where((o) => o.order.status == OrderStatus.readyForPickup)
            .toList();
        final readyForDelivery =
            orders.where((o) => o.order.status == OrderStatus.ready).toList();
        final outForDelivery = orders
            .where((o) => o.order.status == OrderStatus.outForDelivery)
            .toList();

        final sections = <Widget>[];
        void addSection(String label, List<KitchenOrder> items, Color color) {
          if (items.isEmpty) return;
          if (sections.isNotEmpty) {
            sections.add(const SizedBox(height: AppSpacing.lg));
          }
          sections.add(
              _SectionHeader(label: label, count: items.length, color: color));
          sections.add(const SizedBox(height: AppSpacing.sm));
          sections
              .addAll(items.map((ko) => _KitchenOrderCard(kitchenOrder: ko)));
        }

        addSection('Being Sourced', beingSourced, context.colors.statusAmber);
        addSection('Scheduled', placed, context.colors.statusAmber);
        addSection('Preparing', preparing, theme.colorScheme.primary);
        addSection('Awaiting Final Payment', awaitingPayment,
            context.colors.textSecondary);
        addSection(
            'Ready for Pickup', readyForPickup, context.colors.brandText);
        addSection(
            'Ready for Delivery', readyForDelivery, context.colors.brandText);
        addSection(
            'Out for Delivery', outForDelivery, context.colors.statusAmber);

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          children: [
            ...sections,
            const SizedBox(height: AppSpacing.xl),
          ],
        );
      },
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
            color: context.colors.surfaceRaised,
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

  /// Advances through kitchen stages. beingSourced and placed both go to
  /// preparing. preparing branches on delivery_type:
  ///   - pickup → ready_for_pickup
  ///   - Uniflex delivery → ready (already paid in full at checkout)
  ///   - Partner delivery → should not happen (partner orders are read-only)
  Future<void> _advance() async {
    final order = widget.kitchenOrder.order;
    final isPartner = order.source == 'partner';
    // Partner orders are read-only in the kitchen — they should never be
    // advanced from here (rider pool + commitment-fee flow handles them).
    if (isPartner) return;

    final nextStatus = switch (order.status) {
      OrderStatus.beingSourced => 'preparing',
      OrderStatus.placed => 'preparing',
      OrderStatus.preparing => 'ready_for_pickup',
      _ => null,
    };
    if (nextStatus == null) return;
    await _run(() =>
        ref.read(adminServiceProvider).updateOrderStatus(order.id, nextStatus));
  }

  /// Pickup orders only: the customer has physically collected the order.
  Future<void> _markCompleted() async {
    await _run(() => ref
        .read(adminServiceProvider)
        .updateOrderStatus(widget.kitchenOrder.order.id, 'completed'));
  }

  /// Sends the customer a one-off message about this order. Status changes
  /// already push automatically — this is for the things a status cannot
  /// say, like "we're out of jollof, is fried rice okay?".
  Future<void> _messageCustomer() async {
    final order = widget.kitchenOrder.order;
    final sent = await showMessageCustomerSheet(
      context,
      onSend: (message) => ref
          .read(notificationInboxServiceProvider)
          .messageCustomer(orderId: order.id, message: message),
      quickReplies: const [
        'Your order will take a little longer than usual — sorry!',
        'One of your items is finished. Would you like a swap?',
        'Your order is ready at the counter.',
      ],
    );
    if (sent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message sent')),
      );
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _isAdvancing = true);
    try {
      await action();
      // Force an immediate refresh — Realtime may lag or miss events.
      ref.invalidate(kitchenOrdersProvider);
      ref.invalidate(scheduledOrdersProvider);
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
    final isPickup = order.deliveryType == 'pickup';

    // The primary action button changes meaning by status — this is what
    // makes "Ready" a real, actionable checkpoint instead of a dead end
    // (Section 12).
    final isPartner = order.source == 'partner';

    // Partner orders are read-only in the kitchen — no action buttons.
    final (String, VoidCallback)? action = isPartner
        ? null
        : switch (order.status) {
            OrderStatus.beingSourced => ('Start Preparing', _advance),
            OrderStatus.placed => ('Start Preparing', _advance),
            OrderStatus.preparing => ('Mark Ready for Pickup', _advance),
            OrderStatus.awaitingFinalPayment => null,
            OrderStatus.readyForPickup when isPickup => (
                'Mark Completed (Picked Up)',
                _markCompleted
              ),
            _ => null,
          };
    final nextLabel = action?.$1;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: context.colors.border),
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
                  // MULTI-VENDOR badge (Round 7 delivery groups)
                  if (order.deliveryGroupId != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 2),
                      decoration: BoxDecoration(
                        color: context.colors.surfaceRaised,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        'GROUP',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: context.colors.brandText,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  // PARTNER badge
                  if (isPartner) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 2),
                      decoration: BoxDecoration(
                        color: context.colors.surfaceRaised,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        'PARTNER',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: context.colors.textSecondary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  // BULK badge (Phase 6)
                  if (order.isBulk) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 2),
                      decoration: BoxDecoration(
                        color: context.colors.surfaceRaised,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        'BULK',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: context.colors.statusAmber,
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
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Student note ──────────────────────────────────────────────
          if (_expanded && order.notes != null) ...[
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
                    Icons.sticky_note_2_outlined,
                    size: 14,
                    color: context.colors.surfaceRaised,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.notes!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Actions ──────────────────────────────────────────────────
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                // Status changes already notify the customer automatically;
                // this is for anything that needs saying in words.
                AppButton(
                  label: 'Message',
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.small,
                  expand: false,
                  icon: AppIcons.chat,
                  onPressed: _isAdvancing ? null : _messageCustomer,
                ),
                if (nextLabel != null && action != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppButton(
                      label: nextLabel,
                      isLoading: _isAdvancing,
                      onPressed: _isAdvancing ? null : action.$2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(OrderStatus status) {
    return switch (status) {
      OrderStatus.beingSourced => context.colors.statusAmber,
      OrderStatus.placed => context.colors.statusAmber,
      OrderStatus.preparing => Theme.of(context).colorScheme.primary,
      OrderStatus.awaitingFinalPayment => context.colors.textSecondary,
      OrderStatus.ready ||
      OrderStatus.readyForPickup =>
        context.colors.brandText,
      OrderStatus.outForDelivery => context.colors.statusAmber,
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
