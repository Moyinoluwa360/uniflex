import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// "Order #AB12CD34" chip shown on a support-chat bubble (and reused for
/// the attachment above the text box). [refId] is the id of the ONE order
/// the student, rider and Admin all see: the delivery-group id for a
/// delivery, the order id for an errand or pickup. Pass [onTap] where the
/// chip should open that order (Admin).
class SupportOrderChip extends StatelessWidget {
  const SupportOrderChip({
    super.key,
    required this.refId,
    this.onTap,
    this.foreground = AppColors.pureWhite,
  });

  final String refId;
  final VoidCallback? onTap;
  final Color foreground;

  /// Same format as `Order.shortId` / `DeliveryGroup.shortId`.
  static String labelFor(String refId) =>
      'Order #${refId.substring(0, refId.length < 8 ? refId.length : 8).toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chip = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: foreground.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined, size: 12, color: foreground),
          const SizedBox(width: 4),
          Text(
            labelFor(refId),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: foreground, fontSize: 10),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 2),
            Icon(Icons.chevron_right, size: 12, color: foreground),
          ],
        ],
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: chip,
    );
  }
}
