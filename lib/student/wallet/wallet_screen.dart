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
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/format/money.dart';
import '../../shared/widgets/lists/app_list_group.dart';
import '../../shared/widgets/sheets/app_sheet.dart';
import '../../shared/widgets/text/app_section_label.dart';
import '../../shared/widgets/wallet/transaction_row.dart';
import '../../shared/widgets/wallet/wallet_card.dart';
import 'paystack_checkout_page.dart';
import 'saving_plan_screen.dart';
import '../../shared/widgets/inputs/app_text_field.dart';

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
            'Wallet funded! New balance: ${Money.hero(newBalance)}',
          ),
          behavior: SnackBarBehavior.floating,
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
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Retry',
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
      final balance = await ref
          .read(walletServiceProvider)
          .verifyPaystackPayment(reference);
      ref.invalidate(walletBalanceProvider);
      ref.invalidate(walletInfoProvider);
      ref.invalidate(walletTransactionsProvider);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Confirmed. Balance: ${Money.hero(balance)}'),
          behavior: SnackBarBehavior.floating,
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

    return AppSheet.show<double>(
      context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
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
                  // Only a test key may claim no real money moves.
                  EnvConfig.isPaystackTestMode
                      ? 'Minimum ₦100 • Test mode — no real money is moved'
                      : 'Minimum ₦100',
                  style: AppTypography.meta(ctx.colors),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  decoration: const InputDecoration(
                    prefixText: '₦ ',
                    hintText: '500',
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
                AppButton(
                  label: 'Proceed to Pay',
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Navigator.of(ctx).pop(double.parse(controller.text));
                    }
                  },
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
    final c = context.colors;
    final infoAsync = ref.watch(walletInfoProvider);
    final txAsync = ref.watch(walletTransactionsProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          // Home's header balance too, so both screens agree.
          ref.invalidate(walletBalanceProvider);
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

                      // ── Wallet card (balance + virtual account) ────────
                      _WalletSection(
                        infoAsync: infoAsync,
                        van: _van,
                        vanLoading: _vanLoading,
                        onFundTap: _openFundWallet,
                        onRetry: () => ref.invalidate(walletInfoProvider),
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // ── Saving Plan shortcut ───────────────────────────
                      AppListGroup(
                        children: [
                          AppListRow(
                            leadingIcon: AppIcons.savings,
                            title: 'Saving Plan',
                            subtitle:
                                'Set a daily, weekly, or monthly spending budget',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SavingPlanScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.lg),
                      const AppSectionLabel('Transaction history'),
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
                          Icon(AppIcons.orders,
                              size: 48, color: c.textTertiary),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'No transactions yet',
                            style: AppTypography.meta(c),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Grouped Today / Yesterday / Earlier on the phone — the
                // query and the order of `txs` are untouched.
                final groups = _groupByDay(txs);
                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    0,
                    AppSpacing.screenGutter,
                    AppSpacing.navClearanceOf(context) + AppSpacing.md,
                  ),
                  sliver: SliverList.list(
                    children: [
                      for (final g in groups) ...[
                        Padding(
                          padding: const EdgeInsets.only(
                              top: AppSpacing.sm, bottom: AppSpacing.sm),
                          child: AppSectionLabel(g.$1),
                        ),
                        AppListGroup(
                          children: [
                            for (final tx in g.$2) _TransactionTile(tx: tx),
                          ],
                        ),
                      ],
                    ],
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

// ── Wallet card section ───────────────────────────────────────────────────────

/// Maps the wallet + virtual-account data onto the presentational
/// [WalletCard]. Copying the account number is the only behaviour here, and it
/// is the same clipboard call + snackbar as before.
class _WalletSection extends StatelessWidget {
  const _WalletSection({
    required this.infoAsync,
    required this.van,
    required this.vanLoading,
    required this.onFundTap,
    required this.onRetry,
  });

  final AsyncValue<Map<String, dynamic>?> infoAsync;
  final VirtualAccountResult? van;
  final bool vanLoading;
  final VoidCallback onFundTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final v = van;
    return WalletCard(
      balance: infoAsync.hasValue
          ? ((infoAsync.value?['balance'] as num?)?.toDouble() ?? 0)
          : null,
      isLoading: infoAsync.isLoading && !infoAsync.hasValue,
      hasError: infoAsync.hasError && !infoAsync.hasValue,
      onRetry: onRetry,
      onFund: onFundTap,
      accountLoading: vanLoading,
      accountTitle: v == null
          ? null
          : (v.isRealAccount
              ? v.bankName
              : 'Virtual Account (Pending Activation)'),
      accountValue: v == null
          ? null
          : (v.isRealAccount
              ? v.accountNumber
              : 'Awaiting Paystack business verification'),
      onCopyAccount: v?.isRealAccount == true
          ? () {
              Clipboard.setData(ClipboardData(text: v!.accountNumber));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Account number copied'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          : null,
    );
  }
}

// ── Transaction grouping + tile ───────────────────────────────────────────────

/// Splits the already-loaded list into Today / Yesterday / Earlier, keeping
/// the original (newest-first) order.
List<(String, List<WalletTransaction>)> _groupByDay(
    List<WalletTransaction> txs) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final buckets = <String, List<WalletTransaction>>{};
  for (final tx in txs) {
    final l = tx.createdAt.toLocal();
    final day = DateTime(l.year, l.month, l.day);
    final key = day == today
        ? 'Today'
        : day == yesterday
            ? 'Yesterday'
            : 'Earlier';
    buckets.putIfAbsent(key, () => []).add(tx);
  }
  return [for (final e in buckets.entries) (e.key, e.value)];
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.tx});

  final WalletTransaction tx;

  @override
  Widget build(BuildContext context) {
    return TransactionRow(
      title: tx.label,
      dateText: _formatDate(tx.createdAt),
      amount: tx.amount,
      isCredit: tx.type == WalletTxType.credit,
      balanceAfter: tx.balanceAfter,
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
