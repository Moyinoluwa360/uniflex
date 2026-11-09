import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../format/money.dart';

/// One wallet transaction: neutral 40px circle with a direction arrow, the
/// title and date, and the amount. Money in is `brandText` with `+`; money out
/// is `textPrimary` with a real minus — never orange.
class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.title,
    required this.dateText,
    required this.amount,
    required this.isCredit,
    required this.balanceAfter,
  });

  final String title;
  final String dateText;
  final double amount;
  final bool isCredit;
  final double balanceAfter;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSpacing.listRowMin),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.surfaceRaised,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isCredit ? AppIcons.arrowDown : AppIcons.arrowUp,
                size: AppIconSize.small,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm + 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppTypography.body(c)
                          .copyWith(fontWeight: FontWeight.w600)),
                  Text(dateText, style: AppTypography.caption(c)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isCredit ? Money.plus(amount) : Money.minus(amount),
                  style: AppTypography.tabular(
                    AppTypography.body(c).copyWith(
                      fontWeight: FontWeight.w600,
                      color: isCredit ? c.brandText : c.textPrimary,
                    ),
                  ),
                ),
                Text(
                  'Bal: ${Money.format(balanceAfter)}',
                  style: AppTypography.tabular(AppTypography.caption(c)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
