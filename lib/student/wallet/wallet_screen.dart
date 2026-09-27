import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/config/env_config.dart';
import '../../shared/models/wallet_transaction.dart';
import '../../shared/services/auth/auth_providers.dart';
import '../../shared/services/wallet/wallet_providers.dart';
import '../../shared/services/wallet/wallet_service.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/async/retry_section.dart';
import 'paystack_checkout_page.dart';
import 'saving_plan_screen.dart';

/// Student wallet screen — Phase 3:
///   • Prominent balance card with Fund Wallet button
///   • Virtual Account section (attempts Paystack DVA, falls back to
///     the Phase 1 placeholder if business verification not complete)
///   • Saving Plan shortcut
///   • Transaction history (top-ups, order payments, refunds)
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  /// Whether we've already attempted to fetch / create the VAN this
  /// session so we don't re-call the Edge Function on every rebuild.
  bool _vanAttempted = false;
  VirtualAccountResult? _van;
  bool _vanLoading = false;

  @override
  void initState() {
    super.initState();
    // Kick off the VAN fetch on first mount (deferred to avoid calling
    // during build).
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchVan());
  }

  Future<void> _fetchVan() async {
    if (_vanAttempted || !mounted) return;
    setState(() {
      _vanAttempted = true;
      _vanLoading = true;
    });
    try {
      final service = ref.read(walletServiceProvider);
      final result = await service.createVirtualAccount();
      if (mounted) setState(() => _van = result);
    } catch (_) {
      // Silently fall back — the wallet screen is still fully functional
      // without the VAN.
    } finally {
      if (mounted) setState(() => _vanLoading = false);
    }
  }

  /// A collision-resistant, unguessable top-up reference.
  ///
  /// This used to be `UFX-<epoch millis>`, which anyone could enumerate. The
  /// verify Edge Function now also proves the payment belongs to the caller,
  /// but a random reference removes the enumeration surface entirely.
  String _newReference() {
    final rng = Random.secure();
    final suffix = List.generate(
      16,
      (_) => rng.nextInt(16).toRadixString(16),
    ).join();
    return 'UFX-$suffix';
  }

  Future<void> _openFundWallet() async {
    final profile = await ref.read(currentProfileProvider.future);
    final userId = ref.read(authServiceProvider).currentSession?.user.id;
    final email = profile?.email ?? '';
    if (!mounted) return;

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session expired — please sign in again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final amount = await _showAmountSheet();
    if (amount == null || !mounted) return;

    final publicKey = EnvConfig.paystackPublicKey;
    final reference = _newReference();

    // Push the Paystack WebView checkout
    final paystackRef = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => PaystackCheckoutPage(
          publicKey: publicKey,
          email: email,
          amountNaira: amount,
          reference: reference,
          userId: userId,
        ),
        fullscreenDialog: true,
      ),
    );

    if (paystackRef == null || !mounted) return;

    // Verify server-side via Edge Function
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = ref.read(walletServiceProvider);
      final newBalance = await service.verifyPaystackPayment(paystackRef);

      // Refresh all wallet-related providers
      ref.invalidate(walletBalanceProvider);
      ref.invalidate(walletInfoProvider);
      ref.invalidate(walletTransactionsProvider);

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Wallet funded! New balance: ₦${newBalance.toStringAsFixed(2)}',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.emerald,
        ),
      );
    } catch (e) {
      // The money has already left the student's bank at this point, so a
      // failure here must be recoverable rather than silent. Previously only
      // WalletException was caught, so a transport/Edge Function error threw
      // past this and the student saw nothing at all.
      final message = e is WalletException
          ? e.message
          : 'We could not confirm your payment. If you were debited, pull to '
              'refresh in a moment — your balance updates once it clears.';
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Retry',
            textColor: AppColors.pureWhite,
            onPressed: () => _retryVerification(paystackRef),
          ),
        ),
      );
    }
  }

  /// Re-runs verification for a reference whose first attempt failed. Safe to
  /// call repeatedly — the server treats an already-credited reference as a
  /// success and returns the current balance.
  Future<void> _retryVerification(String reference) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final balance =
          await ref.read(walletServiceProvider).verifyPaystackPayment(reference);
      ref.invalidate(walletBalanceProvider);
      ref.invalidate(walletInfoProvider);
      ref.invalidate(walletTransactionsProvider);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Confirmed. Balance: ₦${balance.toStringAsFixed(2)}'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.emerald,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Still could not confirm. Please contact support with your '
            'payment reference.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Shows a bottom sheet for the user to type in a top-up amount.
  /// Returns the entered amount in Naira, or null if dismissed.
  Future<double?> _showAmountSheet() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.screenGutter,
            right: AppSpacing.screenGutter,
            top: AppSpacing.lg,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.lg,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How much would you like to add?',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Minimum ₦100 • Test mode — no real money is moved',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  decoration: InputDecoration(
                    prefixText: '₦ ',
                    hintText: '500',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                  ),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    if (n == null || n < 100) {
                      return 'Enter at least ₦100';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      if (formKey.currentState!.validate()) {
                        Navigator.of(ctx)
                            .pop(double.parse(controller.text));
                      }
                    },
                    child: const Text('Proceed to Pay'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final infoAsync = ref.watch(walletInfoProvider);
    final txAsync = ref.watch(walletTransactionsProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(walletInfoProvider);
          ref.invalidate(walletTransactionsProvider);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenGutter,
                  AppSpacing.xl,
                  AppSpacing.screenGutter,
                  0,
                ),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Wallet', style: theme.textTheme.headlineMedium),
                      const SizedBox(height: AppSpacing.lg),

                      // ── Balance card ───────────────────────────────────
                      _BalanceCard(
                        infoAsync: infoAsync,
                        onFundTap: _openFundWallet,
                        onRetry: () => ref.invalidate(walletInfoProvider),
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // ── Virtual Account card ───────────────────────────
                      _VirtualAccountCard(
                        van: _van,
                        isLoading: _vanLoading,
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // ── Saving Plan shortcut ───────────────────────────
                      _SavingPlanTile(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SavingPlanScreen(),
                          ),
                        ),
                      ),

                      const SizedBox(height: AppSpacing.lg),
                      Text('Transaction history',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
                ),
              ),
            ),

            // ── Transaction list ─────────────────────────────────────────
            txAsync.when(
              loading: () => const SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: RetrySection(
                  message: 'Could not load transactions.',
                  onRetry: () => ref.invalidate(walletTransactionsProvider),
                  compact: true,
                ),
              ),
              data: (txs) {
                if (txs.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xl,
                        horizontal: AppSpacing.screenGutter,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 48,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.25),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'No transactions yet',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    0,
                    AppSpacing.screenGutter,
                    AppSpacing.xl,
                  ),
                  sliver: SliverList.separated(
                    itemCount: txs.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.xs),
                    itemBuilder: (_, i) => _TransactionTile(tx: txs[i]),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Balance card ──────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.infoAsync,
    required this.onFundTap,
    required this.onRetry,
  });

  final AsyncValue<Map<String, dynamic>?> infoAsync;
  final VoidCallback onFundTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.emerald, AppColors.darkEmerald],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available Balance',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.pureWhite.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          infoAsync.when(
            data: (info) => Text(
              '₦${((info?['balance'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
              style: theme.textTheme.headlineLarge?.copyWith(
                color: AppColors.pureWhite,
                fontWeight: FontWeight.w700,
              ),
            ),
            loading: () => const SizedBox(
              height: 36,
              child: CircularProgressIndicator(
                  color: AppColors.pureWhite, strokeWidth: 2),
            ),
            error: (_, __) => Row(
              children: [
                Text(
                  '₦--',
                  style: theme.textTheme.headlineLarge
                      ?.copyWith(color: AppColors.pureWhite),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh,
                      size: 16, color: AppColors.pureWhite),
                  label: const Text('Retry',
                      style: TextStyle(color: AppColors.pureWhite)),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 40,
            child: FilledButton.icon(
              onPressed: onFundTap,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Fund Wallet'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.pureWhite.withValues(alpha: 0.2),
                foregroundColor: AppColors.pureWhite,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  side: BorderSide(
                    color: AppColors.pureWhite.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Virtual Account card ──────────────────────────────────────────────────────

class _VirtualAccountCard extends StatelessWidget {
  const _VirtualAccountCard({required this.van, required this.isLoading});

  final VirtualAccountResult? van;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_outlined,
              size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: isLoading
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Virtual Account',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          )),
                      const SizedBox(height: 4),
                      const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  )
                : van == null
                    ? Text('Virtual account unavailable',
                        style: theme.textTheme.bodySmall)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            van!.isRealAccount
                                ? van!.bankName
                                : 'Virtual Account (Pending Activation)',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            van!.isRealAccount
                                ? van!.accountNumber
                                : 'Awaiting Paystack business verification',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: van!.isRealAccount
                                  ? FontWeight.w600
                                  : null,
                            ),
                          ),
                        ],
                      ),
          ),
          if (van?.isRealAccount == true)
            IconButton(
              icon: const Icon(Icons.copy_outlined, size: 18),
              tooltip: 'Copy account number',
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: van!.accountNumber));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Account number copied'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ── Saving Plan shortcut tile ─────────────────────────────────────────────────

class _SavingPlanTile extends StatelessWidget {
  const _SavingPlanTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.savings_outlined,
                size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Saving Plan',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      )),
                  Text(
                    'Set a daily, weekly, or monthly spending budget',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: theme.colorScheme.primary.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}

// ── Transaction tile ──────────────────────────────────────────────────────────

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.tx});

  final WalletTransaction tx;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCredit = tx.type == WalletTxType.credit;
    final amountColor = isCredit ? AppColors.emerald : AppColors.orange;
    final amountPrefix = isCredit ? '+' : '−';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          // Icon badge
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: amountColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCredit
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              size: 18,
              color: amountColor,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.label, style: theme.textTheme.labelMedium),
                Text(
                  _formatDate(tx.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$amountPrefix₦${tx.amount.toStringAsFixed(0)}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: amountColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Bal: ₦${tx.balanceAfter.toStringAsFixed(0)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final local = dt.toLocal();
    final diff = now.difference(local);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${local.day}/${local.month}/${local.year}';
  }
}
