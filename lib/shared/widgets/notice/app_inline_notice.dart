import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// An in-page notice: `surfaceRaised` box, radius 14, 18px leading icon and
/// 14px secondary text. Errors only change the icon to `dangerText`. **There
/// are no blue, yellow or green tinted variants.**
class AppInlineNotice extends StatelessWidget {
  const AppInlineNotice({
    super.key,
    required String this.text,
    this.icon,
    this.isError = false,
  }) : child = null;

  /// Same box, but with your own content (e.g. text with a tappable link).
  const AppInlineNotice.custom({
    super.key,
    required Widget this.child,
    this.icon,
    this.isError = false,
  }) : text = null;

  final String? text;
  final Widget? child;

  /// Defaults to an info (or error) glyph.
  final IconData? icon;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md - 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                icon ?? (isError ? AppIcons.error : AppIcons.info),
                size: AppIconSize.small,
                color: isError ? c.dangerText : c.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm + 2),
            Expanded(
              child: child ??
                  Text(text!,
                      style: AppTypography.meta(c).copyWith(height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}
