import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../buttons/app_button.dart';
import '../status/app_status_label.dart';
import 'app_card.dart';

/// One order in the Orders list: status + short id, title, a few meta lines,
/// then (only when there is something to do) a hairline and the footer.
///
/// Presentation only: the screen decides what [onCancel] / [onTrack] do and
/// whether they exist. A `null` callback means that button is not drawn.
class OrderSummaryCard extends StatelessWidget {
  const OrderSummaryCard({
    super.key,
    required this.statusText,
    required this.statusTone,
    required this.shortId,
    required this.title,
    this.metaLines = const [],
    this.amountText,
    this.onCancel,
    this.isCancelling = false,
    this.onTrack,
  });

  final String statusText;
  final StatusTone statusTone;
  final String shortId;
  final String title;

  /// 14px secondary lines (vendor, delivery location, ...).
  final List<String> metaLines;

  /// Pre-formatted amount (through `Money`), shown tabular under the meta.
  final String? amountText;

  /// Cancel is `quietDanger`. Pass `null` where the order cannot be cancelled.
  final VoidCallback? onCancel;
  final bool isCancelling;

  /// Track is a small secondary button with a chevron. `null` hides it.
  final VoidCallback? onTrack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasFooter = onCancel != null || onTrack != null;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                  child: AppStatusLabel(tone: statusTone, text: statusText)),
              const SizedBox(width: AppSpacing.sm),
              const Spacer(),
              Text(shortId, style: AppTypography.caption(c)),
            ],
          ),
          const SizedBox(height: 10),
          Text(title, style: AppTypography.title(c)),
          for (final line in metaLines) ...[
            const SizedBox(height: 2),
            Text(line, style: AppTypography.meta(c)),
          ],
          if (amountText != null) ...[
            const SizedBox(height: 2),
            Text(
              amountText!,
              style: AppTypography.tabular(
                AppTypography.body(c).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
          if (hasFooter) ...[
            const SizedBox(height: AppSpacing.md - 4),
            Divider(height: 1, thickness: 1, color: c.border),
            const SizedBox(height: AppSpacing.sm + 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onCancel != null)
                  AppButton(
                    key: const ValueKey('order-cancel'),
                    label: 'Cancel',
                    variant: AppButtonVariant.quietDanger,
                    size: AppButtonSize.small,
                    expand: false,
                    isLoading: isCancelling,
                    onPressed: onCancel,
                  ),
                if (onCancel != null && onTrack != null)
                  const SizedBox(width: AppSpacing.sm),
                if (onTrack != null)
                  AppButton(
                    key: const ValueKey('order-track'),
                    label: 'Track',
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.small,
                    expand: false,
                    trailingIcon: AppIcons.chevronRight,
                    onPressed: onTrack,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
