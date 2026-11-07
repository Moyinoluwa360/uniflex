import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/utils/app_error_mapper.dart';
import '../../shared/models/delivery_group.dart';
import '../../shared/models/order.dart';
import '../../shared/order_breakdown/order_breakdown_provider.dart';
import '../../shared/order_breakdown/order_breakdown_widget.dart';
import '../../shared/utils/local_time.dart';
import '../../shared/services/auth/auth_providers.dart';
import '../../shared/services/supabase/supabase_providers.dart';
import '../../shared/services/wallet/wallet_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/pin/pin_entry_sheet.dart';
import '../ordering/order_repository.dart';
import '../support/support_options_screen.dart';

/// Live order tracking — shows the current order status as a vertical
/// step timeline, refreshable. Supports both individual orders and
/// delivery groups (multi-vendor checkouts shown as one entry).
class OrderTrackingScreen extends ConsumerStatefulWidget {
  const OrderTrackingScreen({super.key, required this.order}) : group = null;

  /// Track a delivery group (multi-vendor delivery order).
  const OrderTrackingScreen.forGroup(
      {super.key, required DeliveryGroup this.group})
      : order = null;

  /// Seed order for standalone tracking. Null when tracking a group.
  final Order? order;

  /// Seed group for delivery-group tracking. Null for standalone orders.
  final DeliveryGroup? group;

  bool get isGroup => group != null;

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  bool _isPayingFinal = false;
  bool _isDeclining = false;

  Future<void> _payFinalAmount(Order o) async {
    final hasPin = await ref.read(profileServiceProvider).hasTransactionPin();
    if (!mounted) return;

    if (!hasPin) {
      final didSet = await showSetPinSheet(context, ref);
      if (!mounted || !didSet) return;
    }

    final pin = await showEnterPinSheet(
      context,
      title: 'Pay final amount',
      subtitle:
          'Enter your 4-digit PIN to pay ₦${o.finalAmount?.toStringAsFixed(0) ?? '—'}.',
    );
    if (pin == null || !mounted) return;

    setState(() => _isPayingFinal = true);

    try {
      final client = ref.read(supabaseClientProvider);
      await client.rpc('pay_final_amount', params: {
        'p_order_id': o.id,
        'p_pin': pin,
      });

      ref.invalidate(walletBalanceProvider);
      ref.invalidate(walletInfoProvider);
      ref.invalidate(walletTransactionsProvider);
      ref.invalidate(studentOrdersProvider);
      ref.invalidate(orderByIdProvider(o.id));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment successful — rider is on the way!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorMapper.map(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPayingFinal = false);
    }
  }

  Future<void> _payGroupFinalAmount(DeliveryGroup g) async {
    final hasPin = await ref.read(profileServiceProvider).hasTransactionPin();
    if (!mounted) return;

    if (!hasPin) {
      final didSet = await showSetPinSheet(context, ref);
      if (!mounted || !didSet) return;
    }

    final pin = await showEnterPinSheet(
      context,
      title: 'Pay for your order',
      subtitle:
          'Enter your 4-digit PIN to pay ₦${g.finalAmount?.toStringAsFixed(0) ?? '—'}.',
    );
    if (pin == null || !mounted) return;

    setState(() => _isPayingFinal = true);

    try {
      final client = ref.read(supabaseClientProvider);
      await client.rpc('pay_group_final_amount', params: {
        'p_group_id': g.id,
        'p_pin': pin,
      });

      ref.invalidate(walletBalanceProvider);
      ref.invalidate(walletInfoProvider);
      ref.invalidate(walletTransactionsProvider);
      ref.invalidate(groupByIdProvider(g.id));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment successful — your rider is on the way!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorMapper.map(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPayingFinal = false);
    }
  }

  Future<void> _declineGroupOrder(DeliveryGroup g) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline this order?'),
        content: const Text(
          'The order will be cancelled. The delivery fee already paid is non-refundable.',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, decline'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeclining = true);

    try {
      final client = ref.read(supabaseClientProvider);
      await client.rpc('decline_group_final_amount', params: {
        'p_group_id': g.id,
      });

      ref.invalidate(groupByIdProvider(g.id));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order declined.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorMapper.map(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeclining = false);
    }
  }

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

  Color _groupStatusColor(DeliveryGroupStatus s) {
    return switch (s) {
      DeliveryGroupStatus.placed => AppColors.info,
      DeliveryGroupStatus.commitmentPaid => AppColors.warning,
      DeliveryGroupStatus.riderAccepted => AppColors.orange,
      DeliveryGroupStatus.awaitingFinalPayment => AppColors.warning,
      DeliveryGroupStatus.outForDelivery => AppColors.orange,
      DeliveryGroupStatus.completed => AppColors.emerald,
      DeliveryGroupStatus.cancelled => AppColors.error,
    };
  }

  List<_Step> _buildSteps(Order o) {
    // Partner/errand orders use the sourcing flow.
    if (o.source == 'partner' || o.isErrand) {
      return const [
        _Step(status: OrderStatus.placed, label: 'Order Placed'),
        _Step(
            status: OrderStatus.beingSourced,
            label: 'Being Sourced — Rider is sourcing your items'),
        _Step(
            status: OrderStatus.awaitingFinalPayment,
            label: 'Awaiting Final Payment'),
        _Step(status: OrderStatus.outForDelivery, label: 'Out for Delivery'),
        _Step(status: OrderStatus.completed, label: 'Delivered'),
      ];
    }

    if (o.isForDelivery) {
      return const [
        _Step(status: OrderStatus.placed, label: 'Order Placed'),
        _Step(status: OrderStatus.preparing, label: 'Preparing'),
        _Step(status: OrderStatus.ready, label: 'Ready'),
        _Step(status: OrderStatus.outForDelivery, label: 'Out for Delivery'),
        _Step(status: OrderStatus.completed, label: 'Delivered'),
      ];
    }

    // Pickup
    return const [
      _Step(status: OrderStatus.placed, label: 'Order Placed'),
      _Step(status: OrderStatus.preparing, label: 'Preparing'),
      _Step(status: OrderStatus.readyForPickup, label: 'Ready for Pickup'),
      _Step(status: OrderStatus.completed, label: 'Picked Up'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isGroup) return _buildGroupTracking(context);
    return _buildOrderTracking(context);
  }

  // ── Group tracking ──────────────────────────────────────────────────

  Widget _buildGroupTracking(BuildContext context) {
    final theme = Theme.of(context);
    final seed = widget.group!;
    final liveAsync = ref.watch(groupByIdProvider(seed.id));

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Track Order ${seed.shortId}',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(groupByIdProvider(seed.id));
              ref.invalidate(orderBreakdownProvider(seed.id));
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: liveAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load this order.',
          onRetry: () => ref.invalidate(groupByIdProvider(seed.id)),
        ),
        data: (liveGroup) {
          final g = liveGroup ?? seed;
          final color = _groupStatusColor(g.status);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.shortId,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Delivery Order',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          g.status.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (g.status == DeliveryGroupStatus.completed) ...[
                  const SizedBox(height: AppSpacing.md),
                  DeliveredCard(completedAt: g.completedAt),
                ],

                const SizedBox(height: AppSpacing.lg),
                Text('Order progress', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.md),

                // Group status timeline
                _GroupStatusTimeline(status: g.status),

                const SizedBox(height: AppSpacing.xl),

                // ── Awaiting final payment card ──────────────────────────
                if (g.status == DeliveryGroupStatus.awaitingFinalPayment &&
                    !g.finalPaymentPaid) ...[
                  _GroupFinalPaymentCard(
                    group: g,
                    isPayingFinal: _isPayingFinal,
                    isDeclining: _isDeclining,
                    onPay: () => _payGroupFinalAmount(g),
                    onDecline: () => _declineGroupOrder(g),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],

                // ── Gift: who it is for (the PIN goes to the recipient) ──
                if (g.isGift) ...[
                  _GiftSenderBanner(
                    nickname: g.giftRecipientNickname,
                    message: g.giftMessage,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],

                // ── Out for delivery — payment confirmed + PIN reminder ──
                // (A gift's PIN is for the recipient to give the rider.)
                if (g.status == DeliveryGroupStatus.outForDelivery &&
                    g.deliveryPin != null &&
                    !g.isGift) ...[
                  _GroupDeliveryConfirmedCard(pin: g.deliveryPin!),
                  const SizedBox(height: AppSpacing.xl),
                ],

                // Delivery location
                if (g.deliveryLocation != null) ...[
                  Text('Delivery to', style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          g.deliveryLocation!,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],

                // Fee summary
                Text('Fee', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '₦${g.commitmentFeeTotal.toStringAsFixed(0)} delivery fee',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                // Per-vendor breakdown
                Text('Your order', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.md),
                OrderBreakdown(orderId: g.id),

                const SizedBox(height: AppSpacing.xl),

                // ── Get help with this order ─────────────────────────────
                if (!g.isTerminal)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.support_agent_outlined, size: 18),
                    label: const Text('Get help with this order'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SupportOptionsScreen(
                          groupId: g.id,
                          groupLabel: '#${g.shortId} · Delivery',
                          orderShortId: g.shortId,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Standalone order tracking ──────────────────────────────────────

  Widget _buildOrderTracking(BuildContext context) {
    final theme = Theme.of(context);
    final liveAsync = ref.watch(orderByIdProvider(widget.order!.id));

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Track Order ${widget.order!.shortId}',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(orderByIdProvider(widget.order!.id)),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: liveAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load this order.',
          onRetry: () => ref.invalidate(orderByIdProvider(widget.order!.id)),
        ),
        data: (liveOrder) {
          final o = liveOrder ?? widget.order!;
          final steps = _buildSteps(o);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.shortId,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (o.vendorName != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'from ${o.vendorName}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor(o.status)
                                  .withValues(alpha: 0.15),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Text(
                              o.status.label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: _statusColor(o.status),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (o.estimatedTime != null)
                            Row(
                              children: [
                                const Icon(
                                  Icons.schedule_outlined,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  o.estimatedTime!,
                                  style: theme.textTheme.labelSmall,
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),
                Text('Order progress', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.md),

                // Status timeline
                _StatusTimeline(steps: steps, currentStatus: o.status),

                const SizedBox(height: AppSpacing.xl),

                // ── Being sourced — rider info ───────────────────────────
                if (o.status == OrderStatus.beingSourced) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                          color: AppColors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.shopping_bag_outlined,
                            color: AppColors.orange, size: 20),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your rider is sourcing items',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: AppColors.orange,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'They may flag items as unavailable. '
                                'Check back here for updates.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color:
                                      AppColors.orange.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],

                // ── Awaiting final payment ───────────────────────────────
                if (o.status == OrderStatus.awaitingFinalPayment) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.payment_outlined,
                                color: AppColors.warning, size: 20),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              'Final payment required',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: AppColors.warning,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          o.finalAmount != null
                              ? 'Your rider confirmed the available items. '
                                  'Pay ₦${o.finalAmount!.toStringAsFixed(0)} to continue delivery.'
                              : 'Your rider confirmed the available items. '
                                  'Final amount is being set.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.warning.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (o.finalAmount != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: _isPayingFinal
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.pureWhite),
                              )
                            : const Icon(Icons.lock_outline, size: 18),
                        label: Text(
                          _isPayingFinal
                              ? 'Processing…'
                              : 'Pay Final Amount  ₦${o.finalAmount!.toStringAsFixed(0)}',
                        ),
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.warning),
                        onPressed:
                            _isPayingFinal ? null : () => _payFinalAmount(o),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                ],

                // Delivery info
                if (o.deliveryLocation != null) ...[
                  Text('Delivery to', style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          o.deliveryLocation!,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ],

                // Assigned rider's contact
                if (o.riderId != null) ...[
                  Consumer(
                    builder: (context, ref, _) {
                      final riderInfoAsync =
                          ref.watch(orderRiderInfoProvider(o.id));
                      final info = riderInfoAsync.valueOrNull;
                      if (info == null) return const SizedBox.shrink();
                      final name = info['full_name'] as String?;
                      final phone = info['phone'] as String?;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(AppRadius.card),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.two_wheeler_outlined),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Your rider',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.5),
                                        )),
                                    Text(name ?? 'Assigned',
                                        style: theme.textTheme.bodyMedium),
                                  ],
                                ),
                              ),
                              if (phone != null)
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.phone_outlined,
                                      size: 16),
                                  label: Text(phone),
                                  onPressed: () async {
                                    final uri = Uri.parse('tel:$phone');
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri);
                                    }
                                  },
                                )
                              else
                                Text(
                                  'No number on file',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],

                const SizedBox(height: AppSpacing.xl),

                // Delivery PIN
                if (o.isForDelivery &&
                    o.deliveryPin != null &&
                    !o.status.isTerminal) ...[
                  _TrackingPinCard(pin: o.deliveryPin!),
                  const SizedBox(height: AppSpacing.xl),
                ],

                Text('Total', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '₦${o.totalAmount.toStringAsFixed(0)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                // ── Get help with this order ─────────────────────────────
                if (!o.status.isTerminal)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.support_agent_outlined, size: 18),
                    label: const Text('Get help with this order'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SupportOptionsScreen(
                          orderId: o.id,
                          orderLabel: '#${o.shortId} · ${o.status.label}',
                          orderShortId: o.shortId,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Step {
  const _Step({required this.status, required this.label});
  final OrderStatus status;
  final String label;
}

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({
    required this.steps,
    required this.currentStatus,
  });

  final List<_Step> steps;
  final OrderStatus currentStatus;

  bool _isDone(OrderStatus step) {
    // Find the index of the current status in the steps list
    final stepValues = steps.map((s) => s.status).toList();
    final currentIdx = stepValues.indexOf(currentStatus);
    final stepIdx = stepValues.indexOf(step);
    if (currentIdx < 0 || stepIdx < 0) return false;
    return stepIdx <= currentIdx;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: List.generate(steps.length, (i) {
        final step = steps[i];
        final done = _isDone(step.status);
        final isCurrent = step.status == currentStatus;
        final isLast = i == steps.length - 1;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline column
            SizedBox(
              width: 36,
              child: Column(
                children: [
                  // Dot
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done
                          ? AppColors.emerald
                          : theme.colorScheme.surfaceContainerHighest,
                      border: isCurrent
                          ? Border.all(color: AppColors.emerald, width: 2)
                          : null,
                    ),
                    child: done
                        ? const Icon(
                            Icons.check,
                            color: AppColors.pureWhite,
                            size: 16,
                          )
                        : null,
                  ),
                  // Connector line
                  if (!isLast)
                    Container(
                      width: 2,
                      height: 36,
                      color: done
                          ? AppColors.emerald.withValues(alpha: 0.4)
                          : theme.colorScheme.outline,
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Label
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                step.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                  color: done
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

/// Delivery-group status timeline with fixed steps matching the
/// DeliveryGroupStatus lifecycle.
class _GroupStatusTimeline extends StatelessWidget {
  const _GroupStatusTimeline({required this.status});

  final DeliveryGroupStatus status;

  static const _steps = [
    (status: DeliveryGroupStatus.placed, label: 'Order Placed'),
    (status: DeliveryGroupStatus.riderAccepted, label: 'Rider Accepted'),
    (
      status: DeliveryGroupStatus.awaitingFinalPayment,
      label: 'Final Price Sent'
    ),
    (status: DeliveryGroupStatus.outForDelivery, label: 'Out for Delivery'),
    (status: DeliveryGroupStatus.completed, label: 'Completed'),
  ];

  int _currentIndex() {
    return switch (status) {
      DeliveryGroupStatus.placed => 0,
      DeliveryGroupStatus.commitmentPaid => 0, // still at "placed" step
      DeliveryGroupStatus.riderAccepted => 1,
      DeliveryGroupStatus.awaitingFinalPayment => 2,
      DeliveryGroupStatus.outForDelivery => 3,
      DeliveryGroupStatus.completed => 4,
      DeliveryGroupStatus.cancelled => -1,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _currentIndex();

    if (status == DeliveryGroupStatus.cancelled) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            const Icon(Icons.cancel_outlined, color: AppColors.error, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Order Cancelled',
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: List.generate(_steps.length, (i) {
        final step = _steps[i];
        final done = current >= 0 && i <= current;
        final isCurrent = i == current;
        final isLast = i == _steps.length - 1;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 36,
              child: Column(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done
                          ? AppColors.emerald
                          : theme.colorScheme.surfaceContainerHighest,
                      border: isCurrent
                          ? Border.all(color: AppColors.emerald, width: 2)
                          : null,
                    ),
                    child: done
                        ? const Icon(Icons.check,
                            color: AppColors.pureWhite, size: 16)
                        : null,
                  ),
                  if (!isLast)
                    Container(
                      width: 2,
                      height: 36,
                      color: done
                          ? AppColors.emerald.withValues(alpha: 0.4)
                          : theme.colorScheme.outline,
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                step.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                  color: done
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

/// Pay / Decline card shown when a group is in awaitingFinalPayment state.
class _GroupFinalPaymentCard extends ConsumerWidget {
  const _GroupFinalPaymentCard({
    required this.group,
    required this.isPayingFinal,
    required this.isDeclining,
    required this.onPay,
    required this.onDecline,
  });

  final DeliveryGroup group;
  final bool isPayingFinal;
  final bool isDeclining;
  final VoidCallback onPay;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final walletAsync = ref.watch(walletBalanceProvider);
    final balance = walletAsync.valueOrNull ?? 0.0;
    final finalAmt = group.finalAmount;
    final hasSufficientBalance = finalAmt != null && balance >= finalAmt;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              const Icon(Icons.payment_outlined,
                  color: AppColors.warning, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Pay for your order',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Final amount
          Text(
            '₦${finalAmt?.toStringAsFixed(0) ?? '—'}',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Wallet balance row
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 4),
              Text(
                'Wallet balance: ₦${balance.toStringAsFixed(0)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (finalAmt != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: hasSufficientBalance
                        ? AppColors.emerald.withValues(alpha: 0.12)
                        : AppColors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    hasSufficientBalance ? 'Sufficient' : 'Insufficient',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: hasSufficientBalance
                          ? AppColors.emerald
                          : AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Pay button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (isPayingFinal || isDeclining || finalAmt == null)
                  ? null
                  : onPay,
              child: isPayingFinal
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.pureWhite),
                    )
                  : Text(
                      'Pay ₦${finalAmt?.toStringAsFixed(0) ?? '—'}',
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Decline button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
              ),
              onPressed: (isPayingFinal || isDeclining) ? null : onDecline,
              child: isDeclining
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.error),
                    )
                  : const Text('Decline order'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown to the SENDER of a gift on their order's tracking screen.
class _GiftSenderBanner extends StatelessWidget {
  const _GiftSenderBanner({this.nickname, this.message});

  final String? nickname;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasMessage = message != null && message!.trim().isNotEmpty;
    return Container(
      key: const ValueKey('gift-sender-banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🎁 Gift to ${nickname ?? 'a student'}',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            'You pay and can cancel. They get the food and give the rider '
            'the delivery PIN.',
            style: theme.textTheme.bodySmall,
          ),
          if (hasMessage) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('“${message!.trim()}”',
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}

/// Card shown when a group is outForDelivery — confirms payment and
/// shows the delivery PIN in large individual digit boxes.
class _GroupDeliveryConfirmedCard extends StatelessWidget {
  const _GroupDeliveryConfirmedCard({required this.pin});

  final String pin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.emerald.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: AppColors.emerald, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Payment confirmed',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.emerald,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your rider is on the way. Give them your delivery PIN at the door:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.emerald.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: pin));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('PIN copied'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ...pin.split('').map(
                      (digit) => Container(
                        width: 44,
                        height: 52,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: AppColors.emerald.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.emerald.withValues(alpha: 0.4)),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          digit,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.emerald,
                          ),
                        ),
                      ),
                    ),
                const SizedBox(width: AppSpacing.sm),
                const Icon(Icons.copy_outlined,
                    size: 16, color: AppColors.emerald),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Tap to copy',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.emerald.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// PIN reminder shown on the tracking screen while a delivery is active.
class _TrackingPinCard extends StatelessWidget {
  const _TrackingPinCard({required this.pin});

  final String pin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.emerald.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline,
                  color: AppColors.emerald, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Your Delivery PIN',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.emerald,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: pin));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PIN copied')),
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  pin,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 12,
                    color: AppColors.emerald,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Icon(Icons.copy_outlined,
                    size: 16, color: AppColors.emerald),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Show this to your rider at the door.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.emerald.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Delivered" success card shown at the top of a finished delivery. The time
/// is the server's single `completed_at`, in the phone's local time.
class DeliveredCard extends StatelessWidget {
  const DeliveredCard({super.key, required this.completedAt});

  final DateTime? completedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('delivered-card'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.emerald.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.emerald, size: 32),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Delivered',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.emerald,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (completedAt != null)
                  Text(
                    formatLocalDateTime(completedAt!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
