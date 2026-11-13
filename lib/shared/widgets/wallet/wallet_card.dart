import 'package:flutter/material.dart';

import '../../state/balance_visibility.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../buttons/app_button.dart';
import '../buttons/app_icon_button.dart';
import '../cards/app_card.dart';
import '../format/money.dart';

/// The wallet card: balance (with a hide/show eye), `Fund wallet`, and —
/// only when account data is passed — the virtual-account strip with its
/// copy button, all in one `surface` card (radius 24, padding 20/22/18).
/// No gradient, no coloured fill. With no account data the strip (and its
/// divider) is not drawn at all; the student Wallet passes none while
/// Paystack Dedicated NUBAN is unavailable for the business.
///
/// Presentation only. The balance is hidden by default and shares ONE
/// in-memory show/hide flag with the Home wallet panel
/// ([BalanceVisibility]); it never touches the wallet data, and the account
/// number stays visible so it can be copied.
class WalletCard extends StatefulWidget {
  const WalletCard({
    super.key,
    required this.balance,
    required this.onFund,
    this.isLoading = false,
    this.hasError = false,
    this.onRetry,
    this.accountLoading = false,
    this.accountTitle,
    this.accountValue,
    this.onCopyAccount,
  });

  /// `null` while unknown (loading / error).
  final double? balance;
  final VoidCallback onFund;
  final bool isLoading;
  final bool hasError;
  final VoidCallback? onRetry;

  final bool accountLoading;

  /// Small line above the value (bank name, or the pending title).
  final String? accountTitle;

  /// The account number, or the pending message. `null` + not loading =
  /// "Virtual account unavailable".
  final String? accountValue;

  /// Shown only for a real account.
  final VoidCallback? onCopyAccount;

  @override
  State<WalletCard> createState() => _WalletCardState();
}

class _WalletCardState extends State<WalletCard> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: BalanceVisibility.visible,
      builder: (context, visible, _) => _build(context, hidden: !visible),
    );
  }

  Widget _build(BuildContext context, {required bool hidden}) {
    final c = context.colors;
    final Widget balance;
    if (widget.isLoading) {
      balance = const SizedBox(
        height: 44,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      );
    } else if (widget.hasError || widget.balance == null) {
      balance = Row(
        children: [
          Text('₦--', style: AppTypography.balanceHero(c.textPrimary)),
          const SizedBox(width: AppSpacing.sm),
          if (widget.onRetry != null)
            AppButton(
              label: 'Retry',
              icon: AppIcons.refresh,
              variant: AppButtonVariant.text,
              size: AppButtonSize.small,
              expand: false,
              onPressed: widget.onRetry,
            ),
        ],
      );
    } else if (hidden) {
      // Always exactly four dots, whatever the amount; same style (and so
      // the same line height) as the real figure.
      balance =
          HiddenBalanceText(style: AppTypography.balanceHero(c.textPrimary));
    } else {
      balance =
          MoneyHero(widget.balance!, key: const ValueKey('balance-shown'));
    }

    final hasAccount =
        widget.accountTitle != null && widget.accountValue != null;
    final showAccount = widget.accountLoading || hasAccount;

    return AppCard(
      large: true,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Available Balance',
                    style: AppTypography.sectionLabel(c)),
              ),
              BalanceEyeButton(color: c.textSecondary),
            ],
          ),
          const SizedBox(height: 2),
          balance,
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Fund Wallet',
            icon: AppIcons.add,
            onPressed: widget.onFund,
          ),
          if (showAccount) ...[
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, thickness: 1, color: c.border),
            const SizedBox(height: AppSpacing.md - 2),
            Row(
              key: const ValueKey('account-strip'),
              children: [
                Icon(AppIcons.bank, size: 20, color: c.textSecondary),
                const SizedBox(width: AppSpacing.sm + 4),
                Expanded(
                  child: widget.accountLoading
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Virtual Account',
                                style: AppTypography.caption(c)),
                            const SizedBox(height: 4),
                            const SizedBox(
                              height: 14,
                              width: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ],
                        )
                      : !hasAccount
                          ? Text('Virtual account unavailable',
                              style: AppTypography.meta(c))
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.accountTitle!,
                                    style: AppTypography.caption(c)),
                                const SizedBox(height: 2),
                                Text(
                                  widget.accountValue!,
                                  style: AppTypography.tabular(
                                    AppTypography.body(c).copyWith(
                                      fontWeight: widget.onCopyAccount != null
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                ),
                if (widget.onCopyAccount != null)
                  AppIconButton(
                    icon: AppIcons.copy,
                    semanticLabel: 'Copy account number',
                    onPressed: widget.onCopyAccount,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
