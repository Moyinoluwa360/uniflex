import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/order.dart';
import '../../shared/services/auth/auth_providers.dart';
import '../../shared/services/supabase/supabase_providers.dart';
import '../../shared/services/wallet/wallet_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/buttons/secondary_button.dart';
import '../../shared/widgets/pin/pin_entry_sheet.dart';
import 'order_confirmation_screen.dart';
import 'order_repository.dart';

const _commitmentFee = 300.0;

/// Shown immediately after a partner/around order is placed.
/// Prompts the student to pay a ₦300 commitment fee which moves the
/// order into [OrderStatus.beingSourced] and makes it visible in the
/// rider job pool.
///
/// The student can go back to cancel without paying — the order stays
/// in 'placed' state but no rider is dispatched.
class CommitmentFeeScreen extends ConsumerStatefulWidget {
  const CommitmentFeeScreen({super.key, required this.order});

  final Order order;

  @override
  ConsumerState<CommitmentFeeScreen> createState() =>
      _CommitmentFeeScreenState();
}

class _CommitmentFeeScreenState extends ConsumerState<CommitmentFeeScreen> {
  bool _isLoading = false;
  String? _error;

  Future<void> _pay() async {
    final hasPin =
        await ref.read(profileServiceProvider).hasTransactionPin();
    if (!mounted) return;

    if (!hasPin) {
      final didSet = await showSetPinSheet(context, ref);
      if (!mounted || !didSet) return;
    }

    final pin = await showEnterPinSheet(
      context,
      title: 'Confirm commitment fee',
      subtitle: 'Enter your 4-digit PIN to pay ₦300 and dispatch a rider.',
    );
    if (pin == null || !mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final client = ref.read(supabaseClientProvider);
      await client.rpc('pay_commitment_fee', params: {
        'p_order_id': widget.order.id,
        'p_pin': pin,
      });

      // Invalidate wallet so balance refreshes.
      ref.invalidate(walletBalanceProvider);
      ref.invalidate(walletInfoProvider);
      ref.invalidate(walletTransactionsProvider);
      ref.invalidate(studentOrdersProvider);

      if (!mounted) return;

      // Build a copy of the order with the updated status for the
      // confirmation screen.
      final updatedOrder = widget.order.copyWith(
        status: OrderStatus.beingSourced,
        commitmentFeePaid: true,
        commitmentFeeAmount: _commitmentFee,
      );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OrderConfirmationScreen(order: updatedOrder),
        ),
      );
    } on PostgrestException catch (e) {
      final msg = _mapError(e.message);
      setState(() {
        _isLoading = false;
        _error = msg;
      });
    } catch (e) {
      final msg = _mapError(e.toString());
      setState(() {
        _isLoading = false;
        _error = msg;
      });
    }
  }

  String _mapError(String raw) {
    if (raw.contains('INSUFFICIENT_BALANCE')) {
      return 'Insufficient wallet balance. Please top up and try again.';
    }
    if (raw.contains('INVALID_PIN')) {
      return 'Incorrect PIN. Please try again.';
    }
    if (raw.contains('Commitment fee already paid')) {
      return 'Commitment fee already paid for this order.';
    }
    return 'Payment failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balanceAsync = ref.watch(walletBalanceProvider);
    final balance = balanceAsync.valueOrNull ?? 0.0;
    final hasSufficientBalance = balance >= _commitmentFee;

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Commitment Fee'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Info banner ─────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border:
                    Border.all(color: AppColors.info.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline,
                      color: AppColors.info, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'A ₦300 commitment fee is required to dispatch a rider. '
                      'The rider will source your items and confirm the final cost before delivery. '
                      'This fee is non-refundable.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.info,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── Order reference ─────────────────────────────────────────
            Text('Order', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
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
                    widget.order.shortId,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (widget.order.vendorName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'from ${widget.order.vendorName}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    widget.order.type == 'around'
                        ? 'Around / Errand request'
                        : 'Partner vendor order',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── Fee breakdown ───────────────────────────────────────────
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
                  _FeeRow(
                    label: 'Commitment fee',
                    value: '₦${_commitmentFee.toStringAsFixed(0)}',
                    theme: theme,
                    bold: true,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'This covers the rider going to source your items. '
                    'You will pay the actual food cost separately once the rider confirms what is available.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const Divider(height: AppSpacing.lg),
                  balanceAsync.when(
                    data: (b) => _FeeRow(
                      label: 'Wallet balance',
                      value: '₦${(b ?? 0).toStringAsFixed(0)}',
                      theme: theme,
                      bold: false,
                      valueColor: hasSufficientBalance
                          ? AppColors.emerald
                          : AppColors.error,
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

            // ── Insufficient balance warning ─────────────────────────────
            if (!hasSufficientBalance && balanceAsync.hasValue) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppColors.error, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Insufficient balance to pay the commitment fee. '
                        'Please top up your wallet.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Error ────────────────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.error, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.xl),

            // ── Cancel note ──────────────────────────────────────────────
            Text(
              'If you go back without paying, your order will remain in "placed" state '
              'and no rider will be dispatched.',
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
                label: 'Pay ₦300 and dispatch rider',
                icon: Icons.send_outlined,
                isLoading: _isLoading,
                onPressed: (hasSufficientBalance && !_isLoading) ? _pay : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                label: 'Go back (do not pay yet)',
                onPressed:
                    _isLoading ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  const _FeeRow({
    required this.label,
    required this.value,
    required this.theme,
    required this.bold,
    this.valueColor,
  });

  final String label;
  final String value;
  final ThemeData theme;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: bold ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium,
        ),
        Text(
          value,
          style: (bold
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.labelMedium)
              ?.copyWith(
            color: valueColor ??
                (bold ? theme.colorScheme.primary : null),
          ),
        ),
      ],
    );
  }
}
