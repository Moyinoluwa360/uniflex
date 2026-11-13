import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/utils/app_error_mapper.dart';
import '../../shared/models/delivery_group.dart';
import '../../shared/models/order.dart';
import '../../shared/order_breakdown/order_breakdown_provider.dart';
import '../../shared/order_breakdown/order_breakdown_widget.dart';
import '../../shared/utils/local_time.dart';
import '../../shared/utils/rpc_result.dart';
import '../../shared/services/auth/auth_providers.dart';
import '../../shared/services/supabase/supabase_providers.dart';
import '../../shared/services/wallet/wallet_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/cards/app_card.dart';
import '../../shared/widgets/format/money.dart';
import '../../shared/widgets/lists/app_list_group.dart';
import '../../shared/widgets/notice/app_inline_notice.dart';
import '../../shared/widgets/pin/pin_entry_sheet.dart';
import '../../shared/widgets/status/app_status_label.dart';
import '../../shared/widgets/status/status_presentation.dart';
import '../../shared/widgets/text/app_section_label.dart';
import '../../shared/widgets/tracking/pin_digit_boxes.dart';
import '../../shared/widgets/tracking/tracking_stepper.dart';
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
          'Enter your 4-digit PIN to pay ${o.finalAmount != null ? Money.format(o.finalAmount!) : '—'}.',
    );
    if (pin == null || !mounted) return;

    setState(() => _isPayingFinal = true);

    try {
      final client = ref.read(supabaseClientProvider);
      // A wrong / locked PIN comes back as {"error": …} (Pack 2).
      throwIfRpcError(await client.rpc('pay_final_amount', params: {
        'p_order_id': o.id,
        'p_pin': pin,
      }));

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
          'Enter your 4-digit PIN to pay ${g.finalAmount != null ? Money.format(g.finalAmount!) : '—'}.',
    );
    if (pin == null || !mounted) return;

    setState(() => _isPayingFinal = true);

    try {
      final client = ref.read(supabaseClientProvider);
      // A wrong / locked PIN comes back as {"error": …} (Pack 2).
      throwIfRpcError(await client.rpc('pay_group_final_amount', params: {
        'p_group_id': g.id,
        'p_pin': pin,
      }));

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
    final confirmed = await AppDialog.show(
      context,
      title: 'Decline this order?',
      body:
          'The order will be cancelled. The delivery fee already paid is non-refundable.',
      secondaryLabel: 'Keep order',
      confirmLabel: 'Yes, decline',
      destructive: true,
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
    final c = context.colors;
    final seed = widget.group!;
    final liveAsync = ref.watch(groupByIdProvider(seed.id));

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Track Order ${seed.shortId}',
        actions: [
          IconButton(
            icon: const Icon(AppIcons.refresh),
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
          final status = StatusPresenter.group(g.status);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header card
                SizedBox(
                  width: double.infinity,
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.shortId, style: AppTypography.title(c)),
                        const SizedBox(height: 2),
                        Text('Delivery Order', style: AppTypography.meta(c)),
                        const SizedBox(height: AppSpacing.sm),
                        AppStatusLabel(tone: status.tone, text: status.label),
                      ],
                    ),
                  ),
                ),

                if (g.status == DeliveryGroupStatus.completed) ...[
                  const SizedBox(height: AppSpacing.md),
                  DeliveredCard(completedAt: g.completedAt),
                ],

                const SizedBox(height: AppSpacing.lg),
                const AppSectionLabel('Order progress'),
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
                  const AppSectionLabel('Delivery to'),
                  const SizedBox(height: AppSpacing.sm),
                  AppListGroup(
                    children: [
                      AppListRow(
                        leadingIcon: AppIcons.location,
                        title: g.deliveryLocation!,
                        showChevron: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],

                // Fee summary
                const AppSectionLabel('Fee'),
                const SizedBox(height: 4),
                Text(
                  '${Money.format(g.commitmentFeeTotal)} delivery fee',
                  style: AppTypography.tabular(AppTypography.title(c)),
                ),

                const SizedBox(height: AppSpacing.xl),

                // Per-vendor breakdown
                const AppSectionLabel('Your order'),
                const SizedBox(height: AppSpacing.md),
                OrderBreakdown(orderId: g.id),

                const SizedBox(height: AppSpacing.xl),

                // ── Get help with this order ─────────────────────────────
                if (!g.isTerminal)
                  AppButton(
                    icon: AppIcons.chat,
                    label: 'Get help with this order',
                    variant: AppButtonVariant.secondary,
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
    final c = context.colors;
    final liveAsync = ref.watch(orderByIdProvider(widget.order!.id));

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Track Order ${widget.order!.shortId}',
        actions: [
          IconButton(
            icon: const Icon(AppIcons.refresh),
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
          final status = StatusPresenter.order(o.status);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header card
                SizedBox(
                  width: double.infinity,
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.shortId, style: AppTypography.title(c)),
                        if (o.vendorName != null) ...[
                          const SizedBox(height: 2),
                          Text('from ${o.vendorName}',
                              style: AppTypography.meta(c)),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Flexible(
                              child: AppStatusLabel(
                                  tone: status.tone, text: status.label),
                            ),
                            const Spacer(),
                            if (o.estimatedTime != null)
                              Row(
                                children: [
                                  Icon(AppIcons.clock,
                                      size: 14, color: c.textTertiary),
                                  const SizedBox(width: 4),
                                  Text(o.estimatedTime!,
                                      style: AppTypography.caption(c)),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),
                const AppSectionLabel('Order progress'),
                const SizedBox(height: AppSpacing.md),

                // Status timeline
                _StatusTimeline(steps: steps, currentStatus: o.status),

                const SizedBox(height: AppSpacing.xl),

                // ── Being sourced — rider info ───────────────────────────
                if (o.status == OrderStatus.beingSourced) ...[
                  AppInlineNotice.custom(
                    icon: AppIcons.cart,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your rider is sourcing items',
                          style: AppTypography.meta(c).copyWith(
                            color: c.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'They may flag items as unavailable. '
                          'Check back here for updates.',
                          style: AppTypography.meta(c),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],

                // ── Awaiting final payment ───────────────────────────────
                if (o.status == OrderStatus.awaitingFinalPayment) ...[
                  AppInlineNotice.custom(
                    icon: AppIcons.wallet,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Final payment required',
                          style: AppTypography.meta(c).copyWith(
                            color: c.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          o.finalAmount != null
                              ? 'Your rider confirmed the available items. '
                                  'Pay ${Money.format(o.finalAmount!)} to continue delivery.'
                              : 'Your rider confirmed the available items. '
                                  'Final amount is being set.',
                          style: AppTypography.meta(c),
                        ),
                      ],
                    ),
                  ),
                  if (o.finalAmount != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      icon: AppIcons.lock,
                      label: _isPayingFinal
                          ? 'Processing…'
                          : 'Pay Final Amount  ${Money.format(o.finalAmount!)}',
                      isLoading: _isPayingFinal,
                      onPressed:
                          _isPayingFinal ? null : () => _payFinalAmount(o),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                ],

                // Delivery info
                if (o.deliveryLocation != null) ...[
                  const AppSectionLabel('Delivery to'),
                  const SizedBox(height: AppSpacing.sm),
                  AppListGroup(
                    children: [
                      AppListRow(
                        leadingIcon: AppIcons.location,
                        title: o.deliveryLocation!,
                        showChevron: false,
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
                        padding: const EdgeInsets.only(
                            top: AppSpacing.md, bottom: AppSpacing.xl),
                        child: SizedBox(
                          width: double.infinity,
                          child: AppCard(
                            child: Row(
                              children: [
                                Icon(AppIcons.rider,
                                    color: c.textSecondary, size: 22),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Your rider',
                                          style: AppTypography.caption(c)),
                                      Text(name ?? 'Assigned',
                                          style: AppTypography.body(c)),
                                    ],
                                  ),
                                ),
                                if (phone != null)
                                  AppButton(
                                    icon: AppIcons.phone,
                                    label: phone,
                                    variant: AppButtonVariant.secondary,
                                    size: AppButtonSize.small,
                                    expand: false,
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
                                    style: AppTypography.caption(c),
                                  ),
                              ],
                            ),
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

                const AppSectionLabel('Total'),
                const SizedBox(height: 4),
                Text(
                  Money.format(o.totalAmount),
                  style: AppTypography.tabular(AppTypography.title(c)),
                ),

                const SizedBox(height: AppSpacing.xl),

                // ── Get help with this order ─────────────────────────────
                if (!o.status.isTerminal)
                  AppButton(
                    icon: AppIcons.chat,
                    label: 'Get help with this order',
                    variant: AppButtonVariant.secondary,
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

  @override
  Widget build(BuildContext context) {
    // Find the index of the current status in the steps list.
    final stepValues = steps.map((s) => s.status).toList();
    final currentIdx = stepValues.indexOf(currentStatus);
    final states = List.generate(steps.length, (i) {
      if (currentIdx < 0 || i > currentIdx) return TrackingStepState.upcoming;
      // The last step (delivered / picked up) is finished, not "in progress".
      if (i == currentIdx && currentStatus != OrderStatus.completed) {
        return TrackingStepState.current;
      }
      return TrackingStepState.done;
    });
    return TrackingStepper(
      labels: [for (final s in steps) s.label],
      states: states,
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
    final current = _currentIndex();

    if (status == DeliveryGroupStatus.cancelled) {
      return const AppInlineNotice(
        isError: true,
        icon: AppIcons.error,
        text: 'Order Cancelled',
      );
    }

    final states = List.generate(_steps.length, (i) {
      if (current < 0 || i > current) return TrackingStepState.upcoming;
      if (i == current && status != DeliveryGroupStatus.completed) {
        return TrackingStepState.current;
      }
      return TrackingStepState.done;
    });
    return TrackingStepper(
      labels: [for (final s in _steps) s.label],
      states: states,
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
    final c = context.colors;
    final walletAsync = ref.watch(walletBalanceProvider);
    final balance = walletAsync.valueOrNull ?? 0.0;
    final finalAmt = group.finalAmount;
    final hasSufficientBalance = finalAmt != null && balance >= finalAmt;

    return SizedBox(
      width: double.infinity,
      child: AppCard(
        strongBorder: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                Icon(AppIcons.wallet, color: c.textSecondary, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Pay for your order',
                  style: AppTypography.meta(c).copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            // Final amount
            Text(
              finalAmt != null ? Money.format(finalAmt) : '—',
              style: AppTypography.tabular(
                  Theme.of(context).textTheme.headlineMedium!),
            ),
            const SizedBox(height: AppSpacing.sm),

            // Wallet balance row
            Row(
              children: [
                Icon(AppIcons.wallet, size: 16, color: c.textTertiary),
                const SizedBox(width: 4),
                Text(
                  'Wallet balance: ${Money.format(balance)}',
                  style: AppTypography.tabular(AppTypography.meta(c)),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (finalAmt != null)
                  Text(
                    hasSufficientBalance ? 'Sufficient' : 'Insufficient',
                    style: AppTypography.caption(c).copyWith(
                      color: hasSufficientBalance ? c.brandText : c.dangerText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Pay button
            AppButton(
              label: 'Pay ${finalAmt != null ? Money.format(finalAmt) : '—'}',
              isLoading: isPayingFinal,
              onPressed: (isPayingFinal || isDeclining || finalAmt == null)
                  ? null
                  : onPay,
            ),
            const SizedBox(height: AppSpacing.sm),

            // Decline button
            AppButton(
              label: 'Decline order',
              variant: AppButtonVariant.quietDanger,
              isLoading: isDeclining,
              onPressed: (isPayingFinal || isDeclining) ? null : onDecline,
            ),
          ],
        ),
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
    final c = context.colors;
    final hasMessage = message != null && message!.trim().isNotEmpty;
    return SizedBox(
      key: const ValueKey('gift-sender-banner'),
      width: double.infinity,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🎁 Gift to ${nickname ?? 'a student'}',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(
              'You pay and can cancel. They get the food and give the rider '
              'the delivery PIN.',
              style: AppTypography.meta(c),
            ),
            if (hasMessage) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('“${message!.trim()}”',
                  style: AppTypography.meta(c)
                      .copyWith(fontStyle: FontStyle.italic)),
            ],
          ],
        ),
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
    final c = context.colors;

    return SizedBox(
      width: double.infinity,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(AppIcons.success, color: c.brandText, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Payment confirmed',
                  style: AppTypography.meta(c).copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Your rider is on the way. Give them your delivery PIN at the door:',
              style: AppTypography.meta(c),
            ),
            const SizedBox(height: AppSpacing.md),
            PinDigitBoxes(pin: pin),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tap to copy',
              style: AppTypography.caption(c),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
    final c = context.colors;
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        child: Column(
          children: [
            Row(
              children: [
                Icon(AppIcons.lock, color: c.textSecondary, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Your Delivery PIN',
                  style: AppTypography.meta(c).copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            PinDigitBoxes(pin: pin),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Show this to your rider at the door.',
              style: AppTypography.meta(c),
            ),
          ],
        ),
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
    final c = context.colors;
    return AppCard(
      key: const ValueKey('delivered-card'),
      child: Row(
        children: [
          Icon(AppIcons.success, color: c.brandText, size: 32),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Delivered', style: AppTypography.title(c)),
                if (completedAt != null)
                  Text(
                    formatLocalDateTime(completedAt!),
                    style: AppTypography.meta(c),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
