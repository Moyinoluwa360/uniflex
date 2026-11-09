import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../buttons/app_button.dart';
import '../buttons/app_icon_button.dart';
import '../cards/app_card.dart';
import '../format/money.dart';

/// The wallet card: balance (with a hide/show eye), `Fund wallet`, and the
/// virtual-account strip with its copy button, all in one `surface` card
/// (radius 24, padding 20/22/18). No gradient, no coloured fill.
///
/// Presentation only. Hiding the balance is local UI state — it never
/// touches the wallet data, and the account number stays visible so it can
/// be copied.
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
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
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
    } else if (_hidden) {
      balance = Text(
        '₦ ••••••',
        key: const ValueKey('balance-hidden'),
        style: AppTypography.balanceHero(c.textPrimary),
        maxLines: 1,
      );
    } else {
      balance =
          MoneyHero(widget.balance!, key: const ValueKey('balance-shown'));
    }

    final hasAccount =
        widget.accountTitle != null && widget.accountValue != null;

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
              AppIconButton(
                key: const ValueKey('balance-eye'),
                icon: _hidden ? AppIcons.eyeOff : AppIcons.eye,
                semanticLabel: _hidden ? 'Show balance' : 'Hide balance',
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
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
      ),
    );
  }
}
