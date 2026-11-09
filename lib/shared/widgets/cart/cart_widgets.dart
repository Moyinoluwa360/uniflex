import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../format/money.dart';

/// A quiet quantity stepper: two 32px outlined round-rect buttons (`−` / `+`),
/// no fills, with the quantity between them in tabular figures. Each tap calls
/// back exactly once.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.onMinus,
    required this.onPlus,
  });

  final int quantity;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          key: const ValueKey('step-minus'),
          icon: AppIcons.remove,
          label: 'Decrease quantity',
          onTap: onMinus,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2),
          child: Text(
            '$quantity',
            style: AppTypography.tabular(
              AppTypography.body(c).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        _StepButton(
          key: const ValueKey('step-plus'),
          icon: AppIcons.add,
          label: 'Increase quantity',
          onTap: onPlus,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.buttonSmall),
          side: BorderSide(color: c.borderStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(icon, size: AppIconSize.small, color: c.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// One cart line: optional thumbnail, title, options, a price line, an
/// optional [QuantityStepper], the line total (via `Money`), and an optional
/// remove ✕. Plain data in, callbacks out — it holds no cart logic.
class CartItemRow extends StatelessWidget {
  const CartItemRow({
    super.key,
    required this.title,
    required this.lineTotal,
    this.options,
    this.unitLine,
    this.leading,
    this.quantity,
    this.onMinus,
    this.onPlus,
    this.onRemove,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.screenGutter,
      vertical: AppSpacing.sm,
    ),
  });

  final String title;
  final num lineTotal;
  final String? options;

  /// e.g. `₦1,500 each` (already formatted by the caller through `Money`).
  final String? unitLine;
  final Widget? leading;

  /// The stepper shows when [quantity], [onMinus] and [onPlus] are all given.
  final int? quantity;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final VoidCallback? onRemove;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasStepper = quantity != null && onMinus != null && onPlus != null;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpacing.sm + 4),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.body(c)),
                if (options != null && options!.isNotEmpty)
                  Text(options!, style: AppTypography.caption(c)),
                if (unitLine != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    unitLine!,
                    style: AppTypography.tabular(AppTypography.meta(c)),
                  ),
                ],
              ],
            ),
          ),
          if (hasStepper) ...[
            const SizedBox(width: AppSpacing.sm),
            QuantityStepper(
              quantity: quantity!,
              onMinus: onMinus!,
              onPlus: onPlus!,
            ),
          ],
          const SizedBox(width: AppSpacing.sm),
          MoneyText(
            lineTotal,
            textAlign: TextAlign.right,
            style: AppTypography.body(c).copyWith(fontWeight: FontWeight.w600),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: AppSpacing.xs),
            InkResponse(
              onTap: onRemove,
              radius: 20,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(AppIcons.close,
                    size: AppIconSize.small, color: c.textTertiary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `Subtotal ........ ₦12,300` row used under cart groups.
class CartTotalRow extends StatelessWidget {
  const CartTotalRow({super.key, required this.label, required this.amount, this.strong = false});

  final String label;
  final num amount;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = strong ? AppTypography.body(c) : AppTypography.meta(c);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: base),
        MoneyText(
          amount,
          style: strong
              ? base.copyWith(fontWeight: FontWeight.w700)
              : base.copyWith(color: c.textPrimary),
        ),
      ],
    );
  }
}
