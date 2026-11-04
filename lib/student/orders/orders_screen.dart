import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/delivery_group.dart';
import '../../shared/models/order.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../ordering/cart_provider.dart';
import '../ordering/checkout_screen.dart';
import '../ordering/order_repository.dart';
import '../tracking/errand_tracking_screen.dart';
import '../tracking/order_tracking_screen.dart';

/// Orders screen — three tabs:
///   Cart      — items in the current in-memory cart (not yet placed).
///   Preparing — orders with an active status (placed → ready/out-for-delivery).
///   Completed — completed and cancelled orders.
///
/// Delivery orders appear as a single entry per delivery group (not per
/// vendor leg). Pickup and errand orders appear as individual entries.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Orders'),
          bottom: TabBar(
            indicatorColor: AppColors.emerald,
            labelStyle: Theme.of(context).textTheme.labelMedium,
            unselectedLabelStyle: Theme.of(context).textTheme.labelMedium,
            tabs: const [
              Tab(text: 'Cart'),
              Tab(text: 'Preparing'),
              Tab(text: 'Completed'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CartTab(),
            _ActiveOrdersTab(),
            _CompletedOrdersTab(),
          ],
        ),
      ),
    );
  }
}

// ── Cart tab ─────────────────────────────────────────────────────────────────

class _CartTab extends ConsumerWidget {
  const _CartTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cart = ref.watch(cartProvider);

    if (cart.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.shopping_cart_outlined,
                  size: 36,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Your cart is empty',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Add items from a vendor on the Home tab.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            itemCount: cart.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final item = cart.items[i];
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.quantity}× ${item.product.name}',
                          style: theme.textTheme.labelLarge,
                        ),
                        if (item.optionsSummary.isNotEmpty)
                          Text(
                            item.optionsSummary,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.55),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '₦${item.lineTotal.toStringAsFixed(0)}',
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  GestureDetector(
                    onTap: () =>
                        ref.read(cartProvider.notifier).removeAt(i),
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.4),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // Checkout strip
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.sm,
              AppSpacing.screenGutter,
              AppSpacing.md,
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Subtotal', style: theme.textTheme.bodyMedium),
                    Text(
                      '₦${cart.subtotal.toStringAsFixed(0)}',
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                PrimaryButton(
                  label: 'Proceed to Checkout',
                  icon: Icons.arrow_forward,
                  onPressed: cart.isEmpty
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const CheckoutScreen(),
                            ),
                          ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Active orders tab ─────────────────────────────────────────────────────────

class _ActiveOrdersTab extends ConsumerWidget {
  const _ActiveOrdersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(studentOrdersProvider);
    final groupsAsync = ref.watch(studentDeliveryGroupsProvider);

    return _UnifiedOrderList(
      ordersAsync: ordersAsync,
      groupsAsync: groupsAsync,
      filter: (entry) => entry.isActive,
      emptyMessage: 'No active orders',
      emptySubtitle: 'Orders being prepared will appear here.',
      onRefresh: () async {
        ref.invalidate(studentOrdersProvider);
        ref.invalidate(studentDeliveryGroupsProvider);
      },
    );
  }
}

// ── Completed orders tab ──────────────────────────────────────────────────────

class _CompletedOrdersTab extends ConsumerWidget {
  const _CompletedOrdersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(studentOrdersProvider);
    final groupsAsync = ref.watch(studentDeliveryGroupsProvider);

    return _UnifiedOrderList(
      ordersAsync: ordersAsync,
      groupsAsync: groupsAsync,
      filter: (entry) => entry.isTerminal,
      emptyMessage: 'No completed orders yet',
      emptySubtitle: 'Your order history will appear here.',
      onRefresh: () async {
        ref.invalidate(studentOrdersProvider);
        ref.invalidate(studentDeliveryGroupsProvider);
      },
    );
  }
}

// ── Unified list widget ─────────────────────────────────────────────────────

class _UnifiedOrderList extends ConsumerWidget {
  const _UnifiedOrderList({
    required this.ordersAsync,
    required this.groupsAsync,
    required this.filter,
    required this.emptyMessage,
    required this.emptySubtitle,
    required this.onRefresh,
  });

  final AsyncValue<List<Order>> ordersAsync;
  final AsyncValue<List<DeliveryGroup>> groupsAsync;
  final bool Function(StudentOrderEntry) filter;
  final String emptyMessage;
  final String emptySubtitle;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Wait for both to load.
    if (ordersAsync.isLoading || groupsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (ordersAsync.hasError) {
      return RetrySection(
        message: 'Could not load orders.',
        onRetry: () {
          ref.invalidate(studentOrdersProvider);
          ref.invalidate(studentDeliveryGroupsProvider);
        },
      );
    }

    final orders = ordersAsync.valueOrNull ?? [];
    final groups = groupsAsync.valueOrNull ?? [];

    // Build unified entries:
    // - Standalone orders: orders with no delivery_group_id (pickup, errand)
    // - Delivery groups: one entry per group (replaces per-vendor legs)
    final deliveryGroupIds =
        groups.map((g) => g.id).toSet();
    final standaloneOrders = orders
        .where((o) => o.deliveryGroupId == null ||
            !deliveryGroupIds.contains(o.deliveryGroupId))
        .map((o) => StudentOrderEntry.fromOrder(o));
    final groupEntries =
        groups.map((g) => StudentOrderEntry.fromGroup(g));

    final all = [...standaloneOrders, ...groupEntries]
        .where(filter)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (all.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary
                      .withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.receipt_long_outlined,
                  size: 36,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(emptyMessage, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Text(
                emptySubtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface
                      .withValues(alpha: 0.55),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        itemCount: all.length,
        separatorBuilder: (_, __) =>
            const SizedBox(height: AppSpacing.cardGap),
        itemBuilder: (context, i) {
          final entry = all[i];
          if (entry.isGroup) {
            return _GroupCard(group: entry.group!);
          }
          return _OrderCard(order: entry.order!);
        },
      ),
    );
  }
}

// ── Order card (standalone: pickup / errand) ────────────────────────────────

class _OrderCard extends ConsumerStatefulWidget {
  const _OrderCard({required this.order});
  final Order order;

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  bool _isCancelling = false;

  Color _statusColor(OrderStatus s) {
    return switch (s) {
      OrderStatus.placed => AppColors.info,
      OrderStatus.preparing => AppColors.warning,
      OrderStatus.ready || OrderStatus.readyForPickup => AppColors.emerald,
      OrderStatus.outForDelivery => AppColors.orange,
      OrderStatus.completed => AppColors.emerald,
      OrderStatus.cancelled => AppColors.error,
      OrderStatus.beingSourced => AppColors.orange,
      OrderStatus.awaitingFinalPayment => AppColors.warning,
    };
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel order?'),
        content: const Text(
            'Are you sure you want to cancel this order? '
            'No fees will be automatically refunded.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep order'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cancel order',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isCancelling = true);
    try {
      await cancelOrder(ref, widget.order.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mapCancelError(e.toString())),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = widget.order;
    final color = _statusColor(order.status);
    final canCancel = !order.status.isTerminal && order.riderId == null;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: theme.dividerColor),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                order.shortId,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (order.vendorName != null)
                Text(
                  '• ${order.vendorName}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  order.status.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.isErrand ? 'ERRAND' : 'Food Delivery',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  Text(
                    '₦${order.totalAmount.toStringAsFixed(0)}',
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
              Row(
                children: [
                  if (canCancel)
                    TextButton(
                      onPressed: _isCancelling ? null : _cancel,
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.error),
                      child: _isCancelling
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Cancel'),
                    ),
                  if (!order.status.isTerminal) ...[
                    if (canCancel) const SizedBox(width: 4),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => order.isErrand
                              ? ErrandTrackingScreen(order: order)
                              : OrderTrackingScreen(order: order),
                        ),
                      ),
                      icon: const Icon(Icons.location_on_outlined, size: 18),
                      label: const Text('Track'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.emerald,
                        foregroundColor: AppColors.pureWhite,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm + 2,
                        ),
                        minimumSize: const Size(80, 44),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Group card (delivery orders) ─────────────────────────────────────────────

class _GroupCard extends ConsumerStatefulWidget {
  const _GroupCard({required this.group});
  final DeliveryGroup group;

  @override
  ConsumerState<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends ConsumerState<_GroupCard> {
  bool _isCancelling = false;

  Color _statusColor(DeliveryGroupStatus s) {
    return switch (s) {
      DeliveryGroupStatus.placed => AppColors.info,
      DeliveryGroupStatus.commitmentPaid => AppColors.warning,
      DeliveryGroupStatus.awaitingFinalPayment => AppColors.warning,
      DeliveryGroupStatus.outForDelivery => AppColors.orange,
      DeliveryGroupStatus.completed => AppColors.emerald,
      DeliveryGroupStatus.cancelled => AppColors.error,
    };
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel order?'),
        content: const Text(
            'Are you sure you want to cancel this delivery order? '
            'No fees will be automatically refunded.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep order'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cancel order',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isCancelling = true);
    try {
      await cancelDeliveryGroup(ref, widget.group.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mapCancelError(e.toString())),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = widget.group;
    final color = _statusColor(group.status);
    final canCancel = !group.isTerminal && group.riderId == null;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: theme.dividerColor),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                group.shortId,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '• Delivery',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  group.status.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Food Delivery',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  if (group.deliveryLocation != null)
                    Text(
                      group.deliveryLocation!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  Text(
                    '₦${group.commitmentFeeTotal.toStringAsFixed(0)} fee',
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
              Row(
                children: [
                  if (canCancel)
                    TextButton(
                      onPressed: _isCancelling ? null : _cancel,
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.error),
                      child: _isCancelling
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Cancel'),
                    ),
                  if (!group.isTerminal) ...[
                    if (canCancel) const SizedBox(width: 4),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              OrderTrackingScreen.forGroup(group: group),
                        ),
                      ),
                      icon: const Icon(Icons.location_on_outlined, size: 18),
                      label: const Text('Track'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.emerald,
                        foregroundColor: AppColors.pureWhite,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm + 2,
                        ),
                        minimumSize: const Size(80, 44),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
