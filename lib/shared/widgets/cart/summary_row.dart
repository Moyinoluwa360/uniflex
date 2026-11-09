import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// `Label ........ ₦1,200` row for order / payment summaries.
///
/// [value] arrives already formatted (through `Money`). Amounts are tabular.
/// [bold] makes the label and value Title-weight (the total line). Pass
/// [valueColor] only for a meaningful tone (`brandText` = fine, `dangerText` =
/// problem).
class SummaryRow extends StatelessWidget {
  const SummaryRow({
    super.key,
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: bold ? text.titleSmall : text.bodyMedium,
            ),
          ),
          Text(
            value,
            style: AppTypography.tabular(
              (bold ? text.titleSmall : text.labelMedium)!
                  .copyWith(color: valueColor ?? c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
