import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/delivery_group.dart';
import '../../shared/models/order.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/cards/app_card.dart';
import '../../shared/widgets/cards/order_summary_card.dart';
import '../../shared/widgets/cart/cart_widgets.dart';
import '../../shared/models/vendor.dart';
import '../../shared/widgets/format/money.dart';
import '../../shared/widgets/status/status_presentation.dart';
import '../../shared/widgets/tabs/app_segmented_tabs.dart';
import '../gifts/gift_models.dart';
import '../gifts/gift_received_screen.dart';
import '../gifts/gift_repository.dart';
import '../ordering/cart_provider.dart';
import '../ordering/checkout_screen.dart';
import '../ordering/order_repository.dart';
import '../tracking/errand_tracking_screen.dart';
import '../tracking/order_tracking_screen.dart';

/// Orders screen — three tabs:
///   Cart      — items in the current in-memory cart (not yet placed).
///   Active    — orders with an active status (placed → ready/out-for-delivery).
///   Completed — completed and cancelled orders.
///
/// Delivery orders appear as a single entry per delivery group (not per
/// vendor leg). Pickup and errand orders appear as individual entries.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final activeCount = _activeCount(
      ref.watch(studentOrdersProvider),
      ref.watch(studentDeliveryGroupsProvider),
      ref.watch(receivedGiftsProvider),
    );
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenGutter,
                  AppSpacing.md,
                  AppSpacing.screenGutter,
                  0,
                ),
                child: Text('Orders', style: AppTypography.heading(c)),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenGutter),
                child: Builder(
                  builder: (context) => AppSegmentedTabs(
                    controller: DefaultTabController.of(context),
                    labels: const ['Cart', 'Active', 'Completed'],
                    counts: [null, activeCount, null],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Expanded(
                child: TabBarView(
                  children: [
                    _CartTab(),
                    _ActiveOrdersTab(),
                    _CompletedOrdersTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every entry the Orders tabs can show (standalone orders, delivery groups,
/// received gifts) — one place so the list and the Active count always agree.
List<StudentOrderEntry> _allEntries(
  List<Order> orders,
  List<DeliveryGroup> groups,
  List<GiftDelivery> gifts,
) {
  // Build unified entries:
  // - Standalone orders: orders with no delivery_group_id (pickup, errand)
  // - Delivery groups: one entry per group (replaces per-vendor legs)
  final standaloneOrders = orders
      // A vendor part (it has a delivery_group_id) is NEVER listed on its
      // own — only its checkout is.
      .where((o) => o.deliveryGroupId == null)
      .map((o) => StudentOrderEntry.fromOrder(o));
  final groupEntries = groups.map((g) => StudentOrderEntry.fromGroup(g));
  final giftEntries = gifts.map((g) => StudentOrderEntry.fromGift(g));
  return [...standaloneOrders, ...groupEntries, ...giftEntries];
}

/// Count shown on the Active tab; `null` (hidden) while loading or when 0.
int? _activeCount(
  AsyncValue<List<Order>> ordersAsync,
  AsyncValue<List<DeliveryGroup>> groupsAsync,
  AsyncValue<List<GiftDelivery>> giftsAsync,
) {
  if (ordersAsync.isLoading || groupsAsync.isLoading) return null;
  if (ordersAsync.hasError) return null;
  final n = _allEntries(
    ordersAsync.valueOrNull ?? [],
    groupsAsync.valueOrNull ?? [],
    giftsAsync.valueOrNull ?? const <GiftDelivery>[],
  ).where((e) => e.isActive).length;
  return n == 0 ? null : n;
}

// ── Cart tab ─────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl + AppSpacing.navClearanceOf(context),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: c.textTertiary),
            const SizedBox(height: AppSpacing.md),
            Text(title,
                style: AppTypography.title(c), textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(subtitle,
                style: AppTypography.meta(c), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _CartTab extends ConsumerWidget {
  const _CartTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final cart = ref.watch(cartProvider);

    if (cart.isEmpty) {
      return const _EmptyState(
        icon: AppIcons.cart,
        title: 'Your cart is empty',
        subtitle: 'Add items from a vendor on the Home tab.',
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              0,
              AppSpacing.screenGutter,
              AppSpacing.md,
            ),
            children: [
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Column(
                  children: [
                    for (var i = 0; i < cart.items.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, thickness: 1, color: c.border),
                      Builder(builder: (context) {
                        final item = cart.items[i];
                        final fixed = cart.groups[item.product.vendorId]?.vendor
                                .isFixedMenu ??
                            false;
                        if (fixed) {
                          // Fixed-menu line: plain item row with a stepper
                          // (0 removes it; at most kFixedMenuMaxQty).
                          final notifier = ref.read(cartProvider.notifier);
                          return CartItemRow(
                            title: item.product.name,
                            unitLine: '${Money.format(item.unitTotal)} each',
                            lineTotal: item.lineTotal,
                            quantity: item.quantity,
                            onMinus: () =>
                                notifier.updateQuantity(i, item.quantity - 1),
                            onPlus: () =>
                                notifier.updateQuantity(i, item.quantity + 1),
                            plusEnabled: item.quantity < kFixedMenuMaxQty,
                          );
                        }
                        return CartItemRow(
                          title: '${item.quantity}× ${item.product.name}',
                          options: item.optionsSummary,
                          lineTotal: item.lineTotal,
                          onRemove: () =>
                              ref.read(cartProvider.notifier).removeAt(i),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        // Checkout strip
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.sm,
            AppSpacing.screenGutter,
            AppSpacing.navClearanceOf(context),
          ),
          child: Column(
            children: [
              CartTotalRow(
                  label: 'Subtotal', amount: cart.subtotal, strong: true),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'Proceed to Checkout',
                icon: AppIcons.forward,
                onPressed: cart.isEmpty
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const CheckoutScreen(),
                          ),
                        ),
              ),
            ],
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
    final giftsAsync = ref.watch(receivedGiftsProvider);

    return _UnifiedOrderList(
      ordersAsync: ordersAsync,
      groupsAsync: groupsAsync,
      giftsAsync: giftsAsync,
      filter: (entry) => entry.isActive,
      emptyMessage: 'No active orders',
      emptySubtitle: 'Orders being prepared will appear here.',
      onRefresh: () async {
        ref.invalidate(studentOrdersProvider);
        ref.invalidate(studentDeliveryGroupsProvider);
        ref.invalidate(receivedGiftsProvider);
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
    final giftsAsync = ref.watch(receivedGiftsProvider);

    return _UnifiedOrderList(
      ordersAsync: ordersAsync,
      groupsAsync: groupsAsync,
      giftsAsync: giftsAsync,
      filter: (entry) => entry.isTerminal,
      emptyMessage: 'No completed orders yet',
      emptySubtitle: 'Your order history will appear here.',
      onRefresh: () async {
        ref.invalidate(studentOrdersProvider);
        ref.invalidate(studentDeliveryGroupsProvider);
        ref.invalidate(receivedGiftsProvider);
      },
    );
  }
}

// ── Unified list widget ─────────────────────────────────────────────────────

class _UnifiedOrderList extends ConsumerWidget {
  const _UnifiedOrderList({
    required this.ordersAsync,
    required this.groupsAsync,
    required this.giftsAsync,
    required this.filter,
    required this.emptyMessage,
    required this.emptySubtitle,
    required this.onRefresh,
  });

  final AsyncValue<List<Order>> ordersAsync;
  final AsyncValue<List<DeliveryGroup>> groupsAsync;

  /// Gifts I received. Never blocks or breaks the list: while loading or on
  /// error it simply contributes nothing.
  final AsyncValue<List<GiftDelivery>> giftsAsync;
  final bool Function(StudentOrderEntry) filter;
  final String emptyMessage;
  final String emptySubtitle;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    final all = _allEntries(
      orders,
      groups,
      giftsAsync.valueOrNull ?? const <GiftDelivery>[],
    ).where(filter).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (all.isEmpty) {
      return _EmptyState(
        icon: AppIcons.orders,
        title: emptyMessage,
        subtitle: emptySubtitle,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          0,
          AppSpacing.screenGutter,
          AppSpacing.navClearanceOf(context) + AppSpacing.md,
        ),
        itemCount: all.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.cardGap),
        itemBuilder: (context, i) {
          final entry = all[i];
          if (entry.isGift) {
            return GiftReceivedCard(gift: entry.gift!);
          }
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

  Future<void> _cancel() async {
    final confirmed = await AppDialog.show(
      context,
      title: 'Cancel order?',
      body: 'Are you sure you want to cancel this order? '
          'No fees will be automatically refunded.',
      secondaryLabel: 'Keep order',
      confirmLabel: 'Cancel order',
      destructive: true,
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
    final order = widget.order;
    final status = StatusPresenter.order(order.status);
    final canCancel = !order.status.isTerminal && order.riderId == null;

    return OrderSummaryCard(
      statusText: status.label,
      statusTone: status.tone,
      shortId: order.shortId,
      title: order.isErrand ? 'ERRAND' : 'Food Delivery',
      metaLines: [if (order.vendorName != null) order.vendorName!],
      amountText: Money.format(order.totalAmount),
      onCancel: canCancel ? _cancel : null,
      isCancelling: _isCancelling,
      onTrack: order.status.isTerminal
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => order.isErrand
                      ? ErrandTrackingScreen(order: order)
                      : OrderTrackingScreen(order: order),
                ),
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

  Future<void> _cancel() async {
    final confirmed = await AppDialog.show(
      context,
      title: 'Cancel order?',
      body: 'Are you sure you want to cancel this delivery order? '
          'No fees will be automatically refunded.',
      secondaryLabel: 'Keep order',
      confirmLabel: 'Cancel order',
      destructive: true,
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
    final group = widget.group;
    final status = StatusPresenter.group(group.status);
    final canCancel = !group.isTerminal && group.riderId == null;

    return OrderSummaryCard(
      statusText: status.label,
      statusTone: status.tone,
      shortId: group.shortId,
      title: 'Food Delivery',
      metaLines: [
        if (group.isGift)
          '🎁 Gift to ${group.giftRecipientNickname ?? 'a student'}',
        if (group.deliveryLocation != null) group.deliveryLocation!,
      ],
      amountText: '${Money.format(group.commitmentFeeTotal)} fee',
      onCancel: canCancel ? _cancel : null,
      isCancelling: _isCancelling,
      onTrack: group.isTerminal
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OrderTrackingScreen.forGroup(group: group),
                ),
              ),
    );
  }
}
