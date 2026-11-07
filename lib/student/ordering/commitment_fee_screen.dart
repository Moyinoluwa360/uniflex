import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/order.dart';
import '../../shared/services/saving_plan/saving_plan_providers.dart';
import '../../shared/services/settings/service_charge_provider.dart';
import '../../shared/services/wallet/wallet_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/utils/uuid_v4.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/buttons/secondary_button.dart';
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
            'Enter your 4-digit PIN to pay ₦${quote.total.toStringAsFixed(0)}.',
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
              _InfoBanner(
                text: isPickup
                    ? 'You pay the full food amount now. There is no delivery '
                        'fee or service charge for pickup.'
                    : 'You pay the delivery fee and a small service charge '
                        'now, and a rider is dispatched. You pay for the food '
                        'after the rider confirms the price.',
              ),
              if (_draft.isGift) ...[
                const SizedBox(height: AppSpacing.md),
                _InfoBanner(
                  key: const ValueKey('gift-pay-banner'),
                  text: '🎁 Gift for ${_draft.giftRecipient!.nickname} '
                      '(${_draft.giftRecipient!.maskedEmail}). You pay and '
                      'you can cancel; they only receive the food.',
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text('Payment', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Column(
                  children: [
                    for (final line in quote.lines)
                      _FeeRow(
                        label: line.label,
                        value: '₦${line.amount.toStringAsFixed(0)}',
                        theme: theme,
                      ),
                    if (!isPickup)
                      serviceAsync.when(
                        data: (v) => _FeeRow(
                          label: 'Service charge',
                          value: '₦${v.toStringAsFixed(0)}',
                          theme: theme,
                        ),
                        loading: () => const SizedBox(
                          height: 24,
                          child: Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: AppColors.error),
                                ),
                              ),
                              TextButton(
                                onPressed: () =>
                                    ref.invalidate(serviceChargeProvider),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const Divider(height: AppSpacing.lg),
                    _FeeRow(
                      label: 'Total',
                      value: feesReady
                          ? '₦${quote.total.toStringAsFixed(0)}'
                          : '—',
                      theme: theme,
                      bold: true,
                    ),
                    if (!isPickup) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Food is paid after the rider confirms the price.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ],
                    const Divider(height: AppSpacing.lg),
                    balanceAsync.when(
                      data: (b) => _FeeRow(
                        label: 'Wallet balance',
                        value: '₦${(b ?? 0).toStringAsFixed(0)}',
                        theme: theme,
                        valueColor:
                            insufficient ? AppColors.error : AppColors.emerald,
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
              if (insufficient || _errorIsBalance) ...[
                const SizedBox(height: AppSpacing.sm),
                _ErrorBox(
                  text: 'Your wallet balance is not enough to pay this.',
                  action: TextButton(
                    onPressed: _goToWallet,
                    child: const Text('Top up your wallet →'),
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
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
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
                PrimaryButton(
                  label: feesReady
                      ? 'Pay ₦${quote.total.toStringAsFixed(0)}'
                      : 'Pay',
                  icon: Icons.lock_outline,
                  isLoading: _isSubmitting,
                  onPressed: (feesReady && !insufficient && !_isSubmitting)
                      ? () => _pay(quote)
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                SecondaryButton(
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

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppColors.info, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.info),
            ),
          ),
        ],
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
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.error),
                ),
              ),
            ],
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  const _FeeRow({
    required this.label,
    required this.value,
    required this.theme,
    this.bold = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final ThemeData theme;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: bold
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            value,
            style: (bold
                    ? theme.textTheme.titleSmall
                    : theme.textTheme.labelMedium)
                ?.copyWith(
              color: valueColor ?? (bold ? theme.colorScheme.primary : null),
            ),
          ),
        ],
      ),
    );
  }
}
