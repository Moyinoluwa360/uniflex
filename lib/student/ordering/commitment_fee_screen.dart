import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/order.dart';
import '../../shared/services/saving_plan/saving_plan_providers.dart';
import '../../shared/services/settings/service_charge_provider.dart';
import '../../shared/services/wallet/wallet_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/utils/uuid_v4.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/cards/app_card.dart';
import '../../shared/widgets/cart/summary_row.dart';
import '../../shared/widgets/format/money.dart';
import '../../shared/widgets/notice/app_inline_notice.dart';
import '../../shared/widgets/navigation/app_bottom_nav_shell.dart';
import '../../shared/widgets/payment/run_payment_flow.dart';
import '../tracking/order_tracking_screen.dart';
import 'cart_provider.dart';
import 'checkout_draft.dart';
import 'order_confirmation_screen.dart';
import 'order_payment_repository.dart';
import 'order_repository.dart';

const _studentWalletTabIndex = 2;

/// The payment page (Pack 4A rebuild of the old "commitment fee" page).
///
/// Shows the student exactly what they are about to pay:
///   * delivery: each vendor's delivery fee as its own line, the service
///     charge once, and the total;
///   * pickup (Uniflex-only cart): the full food amount — no delivery fee,
///     no service charge.
///
/// Paying runs the shared payment step ([runPaymentFlow]: note → PIN) and
/// then makes ONE server call that verifies the PIN, computes every amount,
/// debits the wallet and creates the whole order. Only after that call
/// succeeds is the cart cleared. Backing out, a wrong PIN or an
/// insufficient balance create nothing and leave the cart intact.
class CommitmentFeeScreen extends ConsumerStatefulWidget {
  const CommitmentFeeScreen({super.key, required this.draft});

  /// The checkout choices, held in memory. Nothing exists server-side yet.
  final CheckoutDraft draft;

  @override
  ConsumerState<CommitmentFeeScreen> createState() =>
      _CommitmentFeeScreenState();
}

class _CommitmentFeeScreenState extends ConsumerState<CommitmentFeeScreen> {
  /// One key per payment page. Re-sent unchanged on every retry from this
  /// page, so if the network drops after the server created the order and
  /// the student taps Pay again, the server returns that same order
  /// instead of creating (and charging for) a second one.
  final String _idempotencyKey = newUuidV4();

  /// Set synchronously on tap, before any await, so rapid taps on a laggy
  /// phone can never start two payments.
  bool _inFlight = false;
  bool _isSubmitting = false;
  String? _error;
  bool _errorIsBalance = false;

  CheckoutDraft get _draft => widget.draft;

  String get _ackMessage {
    if (_draft.isPickup) {
      return "You're paying for your order now. It will be prepared for "
          'pickup.';
    }
    if (_draft.isGift) {
      return "You're paying the delivery fee and service charge for a gift to "
          '${_draft.giftRecipient!.nickname}. You also pay for the food after '
          'the rider confirms the price. They are told as soon as you pay.';
    }
    return "You're paying the delivery fee and service charge. Your food is "
        'paid after the rider confirms the price.';
  }

  Future<void> _pay(CheckoutQuote quote) async {
    if (_inFlight) return;
    _inFlight = true;
    setState(() => _error = null);

    // Captured now so the follow-up work (clearing the cart, refreshing
    // wallet/orders) still runs if the page is closed mid-payment.
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = container.read(orderPaymentRepositoryProvider);
    PaidOrderResult? paid;

    try {
      final result = await runPaymentFlow(
        context: context,
        ref: ref,
        acknowledgeMessage: _ackMessage,
        pinTitle:
            _draft.isPickup ? 'Confirm payment' : 'Confirm delivery payment',
        pinSubtitle:
            'Enter your 4-digit PIN to pay ${Money.format(quote.total)}.',
        setSubmitting: (v) {
          if (mounted) setState(() => _isSubmitting = v);
        },
        onError: (message) {
          if (mounted) setState(() => _error = message);
        },
        onConfirm: (pin) async {
          try {
            paid = _draft.isPickup
                ? await repo.payPickup(
                    idempotencyKey: _idempotencyKey,
                    pin: pin,
                    draft: _draft,
                  )
                : await repo.payDelivery(
                    idempotencyKey: _idempotencyKey,
                    pin: pin,
                    draft: _draft,
                  );
          } catch (e) {
            _errorIsBalance = e.toString().contains('INSUFFICIENT_BALANCE');
            rethrow;
          }
        },
      );

      if (result != PaymentFlowResult.success || paid == null) return;

      // ── Paid. Only now does the cart go. ───────────────────────────
      container.read(cartProvider.notifier).clear();
      container.invalidate(walletBalanceProvider);
      container.invalidate(walletInfoProvider);
      container.invalidate(walletTransactionsProvider);
      container.invalidate(studentOrdersProvider);
      container.invalidate(studentDeliveryGroupsProvider);
      container.invalidate(activeSavingPlanProvider);

      if (!mounted) return;
      await _showOutcome(container, paid!);
    } finally {
      _inFlight = false;
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _showOutcome(
      ProviderContainer container, PaidOrderResult r) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (_draft.isPickup) {
      final v = _draft.vendors.first;
      final order = Order(
        id: r.orderId,
        studentId: '',
        vendorId: v.vendorId,
        vendorName: v.vendorName,
        source: 'uniflex',
        type: 'food',
        status: OrderStatus.placed,
        deliveryType: 'pickup',
        totalAmount: r.totalCharged,
        estimatedTime: _draft.scheduledFor != null ? 'Scheduled' : '20–30 min',
        scheduledFor: _draft.scheduledFor,
        packCount: v.packCount,
        packFee: v.packFee,
        createdAt: DateTime.now(),
      );
      if (r.planOverBudget) {
        messenger.showSnackBar(const SnackBar(
          content: Text(
              'Heads up: this order has put you over your saving plan budget for the current period.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 5),
        ));
      }
      await navigator.pushReplacement(
        MaterialPageRoute(
            builder: (_) => OrderConfirmationScreen(order: order)),
      );
      return;
    }

    // Delivery: go to the order's tracking screen (one checkout = one order).
    try {
      final group = await container
          .read(groupByIdProvider(r.orderId).future)
          .timeout(const Duration(seconds: 8));
      if (group != null) {
        navigator.popUntil((route) => route.isFirst);
        await navigator.push(
          MaterialPageRoute(
              builder: (_) => OrderTrackingScreen.forGroup(group: group)),
        );
        return;
      }
    } catch (_) {
      // Fall through to the simple confirmation below.
    }
    navigator.popUntil((route) => route.isFirst);
    messenger.showSnackBar(const SnackBar(
      content: Text('Order confirmed! A rider will be dispatched shortly.'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _goToWallet() {
    ref.read(shellTabRequestProvider.notifier).state = _studentWalletTabIndex;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final balanceAsync = ref.watch(walletBalanceProvider);
    final serviceAsync = ref.watch(serviceChargeProvider);
    final isPickup = _draft.isPickup;

    // Pickup has no service charge, so it never waits on the setting.
    final serviceCharge = isPickup ? 0.0 : (serviceAsync.valueOrNull ?? 0.0);
    final feesReady = isPickup || serviceAsync.hasValue;
    final quote = quoteFor(_draft, serviceCharge);

    final balance = balanceAsync.valueOrNull;
    final insufficient = feesReady && balance != null && balance < quote.total;

    return PopScope(
      // Don't let a back-swipe close the page while money is moving.
      canPop: !_inFlight,
      child: Scaffold(
        appBar: UniflexAppBar(title: isPickup ? 'Payment' : 'Pay delivery fee'),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppInlineNotice(
                text: isPickup
                    ? 'You pay the full food amount now. There is no delivery '
                        'fee or service charge for pickup.'
                    : 'You pay the delivery fee and a small service charge '
                        'now, and a rider is dispatched. You pay for the food '
                        'after the rider confirms the price.',
              ),
              if (_draft.isGift) ...[
                const SizedBox(height: AppSpacing.md),
                AppInlineNotice(
                  key: const ValueKey('gift-pay-banner'),
                  text: '🎁 Gift for ${_draft.giftRecipient!.nickname} '
                      '(${_draft.giftRecipient!.maskedEmail}). You pay and '
                      'you can cancel; they only receive the food.',
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text('Payment', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: AppCard(
                  child: Column(
                    children: [
                      for (final line in quote.lines)
                        SummaryRow(
                          label: line.label,
                          value: Money.format(line.amount),
                        ),
                      if (!isPickup)
                        serviceAsync.when(
                          data: (v) => SummaryRow(
                            label: 'Service charge',
                            value: Money.format(v),
                          ),
                          loading: () => const SizedBox(
                            height: 24,
                            child: Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                          error: (_, __) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Could not load the service charge.',
                                    style: AppTypography.meta(c)
                                        .copyWith(color: c.dangerText),
                                  ),
                                ),
                                AppButton(
                                  variant: AppButtonVariant.text,
                                  size: AppButtonSize.small,
                                  expand: false,
                                  label: 'Retry',
                                  onPressed: () =>
                                      ref.invalidate(serviceChargeProvider),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const Divider(height: AppSpacing.lg),
                      SummaryRow(
                        label: 'Total',
                        value: feesReady ? Money.format(quote.total) : '—',
                        bold: true,
                      ),
                      if (!isPickup) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Food is paid after the rider confirms the price.',
                            style: AppTypography.caption(c),
                          ),
                        ),
                      ],
                      const Divider(height: AppSpacing.lg),
                      balanceAsync.when(
                        data: (b) => SummaryRow(
                          label: 'Wallet balance',
                          value: Money.format(b ?? 0),
                          valueColor: insufficient ? c.dangerText : c.brandText,
                        ),
                        loading: () => const SizedBox(
                          height: 20,
                          child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
              if (insufficient || _errorIsBalance) ...[
                const SizedBox(height: AppSpacing.sm),
                _ErrorBox(
                  text: 'Your wallet balance is not enough to pay this.',
                  action: AppButton(
                    variant: AppButtonVariant.text,
                    size: AppButtonSize.small,
                    expand: false,
                    label: 'Top up your wallet →',
                    onPressed: _goToWallet,
                  ),
                ),
              ],
              if (_error != null && !(insufficient || _errorIsBalance)) ...[
                const SizedBox(height: AppSpacing.sm),
                _ErrorBox(text: _error!),
              ],
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Nothing is ordered until you pay. If you go back, your cart '
                'stays exactly as it is.',
                style: AppTypography.caption(c),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.sm,
              AppSpacing.screenGutter,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppButton(
                  label: feesReady ? 'Pay ${Money.format(quote.total)}' : 'Pay',
                  icon: AppIcons.lock,
                  isLoading: _isSubmitting,
                  onPressed: (feesReady && !insufficient && !_isSubmitting)
                      ? () => _pay(quote)
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                AppButton(
                  variant: AppButtonVariant.secondary,
                  label: 'Go back (do not pay yet)',
                  onPressed:
                      _isSubmitting ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.text, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppInlineNotice.custom(
      isError: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text,
              style: AppTypography.meta(c).copyWith(color: c.dangerText)),
          if (action != null) action!,
        ],
      ),
    );
  }
}
