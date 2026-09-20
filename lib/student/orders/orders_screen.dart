import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/order.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../ordering/cart_provider.dart';
import '../ordering/checkout_screen.dart';
import '../ordering/order_repository.dart';
import '../tracking/order_tracking_screen.dart';

/// Orders screen — three tabs:
///   Cart      — items in the current in-memory cart (not yet placed).
///   Preparing — orders with an active status (placed → ready/out-for-delivery).
///   Completed — completed and cancelled orders.
///
/// Status updates are reflected immediately: pulling down on the active
/// tab or tapping a "Track" button refreshes the live data.
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
                  onPressed: cart.vendor == null
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  CheckoutScreen(vendor: cart.vendor!),
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

  static const _activeStatuses = {
    OrderStatus.placed,
    OrderStatus.preparing,
    OrderStatus.ready,
    OrderStatus.outForDelivery,
    OrderStatus.readyForPickup,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(studentOrdersProvider);
    return _OrderList(
      ordersAsync: ordersAsync,
      filter: (o) => _activeStatuses.contains(o.status),
      emptyMessage: 'No active orders',
      emptySubtitle: 'Orders being prepared will appear here.',
      onRefresh: () => ref.refresh(studentOrdersProvider.future),
    );
  }
}

// ── Completed orders tab ──────────────────────────────────────────────────────

class _CompletedOrdersTab extends ConsumerWidget {
  const _CompletedOrdersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(studentOrdersProvider);
    return _OrderList(
      ordersAsync: ordersAsync,
      filter: (o) =>
          o.status == OrderStatus.completed ||
          o.status == OrderStatus.cancelled,
      emptyMessage: 'No completed orders yet',
      emptySubtitle: 'Your order history will appear here.',
      onRefresh: () => ref.refresh(studentOrdersProvider.future),
    );
  }
}

// ── Shared list widget ────────────────────────────────────────────────────────

class _OrderList extends ConsumerWidget {
  const _OrderList({
    required this.ordersAsync,
    required this.filter,
    required this.emptyMessage,
    required this.emptySubtitle,
    required this.onRefresh,
  });

  final AsyncValue<List<Order>> ordersAsync;
  final bool Function(Order) filter;
  final String emptyMessage;
  final String emptySubtitle;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ordersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => RetrySection(
        message: 'Could not load orders.',
        onRetry: () => ref.invalidate(studentOrdersProvider),
      ),
      data: (orders) {
        final filtered = orders.where(filter).toList();

        if (filtered.isEmpty) {
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
            itemCount: filtered.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppSpacing.cardGap),
            itemBuilder: (context, i) => _OrderCard(order: filtered[i]),
          ),
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});
  final Order order;

  Color _statusColor(BuildContext context, OrderStatus s) {
    return switch (s) {
      OrderStatus.placed => AppColors.info,
      OrderStatus.preparing => AppColors.warning,
      OrderStatus.ready || OrderStatus.readyForPickup => AppColors.emerald,
      OrderStatus.outForDelivery => AppColors.orange,
      OrderStatus.completed => AppColors.emerald,
      OrderStatus.cancelled => AppColors.error,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _statusColor(context, order.status);

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
                    order.isAround ? order.type.toUpperCase() : 'Food Delivery',
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
              if (!order.status.isTerminal)
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OrderTrackingScreen(order: order),
                    ),
                  ),
                  icon: const Icon(Icons.location_on_outlined, size: 16),
                  label: const Text('Track'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
